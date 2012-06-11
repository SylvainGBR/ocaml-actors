open Sys;;
open Unix;;
open ActorsType;;
open ActorsGlobal;;
open Actorssg;;

let rec bonjour q =
  react bj
and bj m =
  match m with
    | ("bonjour", [S s]) -> Printf.printf "%s\n%!" s; bonjour [];
    | _ -> Printf.printf "Wrong Message"; bonjour [];;

let treat_connect i o client =
  let s = input_value i in
  (* mutex_lock n_mutex; *)
  if (Hashtbl.mem nodes s) then begin Printf.printf "This node already exists\n%!"; close_out o;
    (* mutex_unlock n_mutex *) end
  else begin output_value o local_node;
    flush o;
    let ac = create() in
    let t = Thread.create receive_remote (i, s) in
    let hst = {name = s; agent = ac; support = t} in
    Hashtbl.add nodes s hst;
    start ac (fun() -> sender o);
    actors_display();
    nodes_display();
    Printf.printf "Noeud distant : %n\n%!" hst.name end;;
(* mutex_unlock n_mutex;; *)

let rec restart_on_EINTR f x =
  try f x with Unix_error (EINTR, _, _) -> restart_on_EINTR f x;;
    
let install_tcp_server_socket addr =
  let s = socket PF_INET SOCK_STREAM 0 in
  try
    bind s addr;
    listen s 10;
    s
  with z -> close s; raise z;;

let tcp_server treat_connection addr =
  let rec run s =
    let client = restart_on_EINTR accept s in
    let _ = Thread.create treat_connection client in
    run s in
  ignore (signal sigpipe Signal_ignore);
  let server_sock = install_tcp_server_socket addr in
  run server_sock;;

let server () =
  (* Random.init (int_of_float (Unix.time())); *)
  (* local_node := (!local_node) ^ string_of_int (Random.int 1024); *)
  Printf.printf "Local Node : %n\n%!" local_node;
  let port = 4242 in
  Printf.printf "%s\n%!" (string_of_inet_addr ((gethostbyname(gethostname())).h_addr_list.(0)));
     (* let host = (gethostbyname(gethostname())).h_addr_list.(0) in *)
  (* let host = (gethostbyname "127.0.0.1").h_addr_list.(0) in *)
  let host = (gethostbyname "193.55.250.242").h_addr_list.(0) in
  let addr = ADDR_INET (host, port) in
  let treat (client_sock, client_addr as client) =
       (* log information *)
    begin match client_addr with
        ADDR_INET(caller, _) ->
          prerr_endline ("Connection from " ^ string_of_inet_addr caller);
      | ADDR_UNIX _ ->
          prerr_endline "Connection from the Unix domain (???)";
    end;
       (* connection treatment *)
    treat_connect (in_channel_of_descr client_sock) (out_channel_of_descr client_sock) client in
  Thread.create (tcp_server treat) addr;;

let _ = handle_unix_error server () in
Hashtbl.add functions "bonjour" bonjour ;

let rec pipong l = 
  let gs ar m =
    match (ar, m) with
      |(Actor a, ("pong", [I i])) -> Printf.printf "Pong %n\n%!" i; 
          send a ("ping", [I (i+1)]);
          pipong [ar];
      |( x , ("pong", [I i])) -> Printf.printf "Invalid Argument"
      | ( _ , (s, _)) -> Printf.printf "pas bon : %s\n%!" s; pipong [ar] in
  react (gs (List.hd l)) in

Hashtbl.add functions "pipong" pipong ;

let irc_mutex = Mutex.create() in
let irc_on = ref false in
let irc_act = ref creator in

let irc_connections l =
  let connec = Hashtbl.create 13 in

  (* let users_display() =  *)
  (*   Printf.printf "Users : "; *)
  (*   let f a b c = Printf.printf "%s; %!" a; c in *)
  (*   Hashtbl.fold f connec (); *)
  (*   Printf.printf "\n%!" in *)

  let ac = create() in
  Mutex.unlock irc_mutex;
  Hashtbl.add connec "server" ("server", ac);
  let rec irc_server() =
    (* users_display(); *)
    let ircm (h, l) =
      let spread a b =
        match b with
          | ("server", _ ) -> (match l with
              | [S s; S g] -> Printf.printf "<%s> : %s \n%!" g s
              | _ -> failwith "Wrong Message Type Error in irc_connections");
          | ( s , a ) -> (* Printf.printf "Talking to : %s, " s; print_actor a; *) send a ("post", l) in
      match (h, l) with 
        | ("post", [S s; S st]) -> Hashtbl.iter spread connec; irc_server();
        (* | ("post", [S s; S st]) -> let (nam, orig) = Hashtbl.find connec st in *)
        (*                            send orig ("post", [S s; S st]); irc_server(); *)
        | _ -> irc_server() in
    react ircm in
  start ac irc_server;
  let rec connexion_handler() =
    let connexion_request m =

      (* let send_connected a b lst = (\*Creates a list containing all the people connected*\) *)
      (*   match b with *)
      (*     | (s, a) -> (S s) :: (Actor a) :: lst in *)

      match m with
        | ("join", [S s; Actor a]) -> (* let lis = Hashtbl.fold send_connected connec [] in *)
                                      Hashtbl.add connec s (s, a);
                                      (* send a ("connected", lis); *)
                                      send a ("connected", [Actor ac]);
                                      connexion_handler();
        | _ -> Printf.printf "Wrong Message in connexion_request\n%!";
            connexion_handler() in
    react connexion_request in
  connexion_handler() in

Hashtbl.add functions "irc_connections" irc_connections;

let transit_act = create() in

let trans a =
  let tran m =
    match m with
      | ("retour", [S s; Actor ac]) -> irc_act:= ac; send a ("retour", [S s; Actor ac]);
      | _ -> () in
  react tran in

let irc q =
  Mutex.lock irc_mutex;
  match q with 
    | [Actor ac] -> Printf.printf "Irc_on : %b\n%!" (!irc_on); 
        if (!irc_on = false) then begin
          irc_on := true;
          start transit_act (fun ()-> trans ac);
          send creator ("start", [S "irc_connections"; Actor transit_act]) end
        else begin
          print_actor (!irc_act);
          send ac ("retour", [S "irc_connections"; Actor (!irc_act)]);
          Mutex.unlock irc_mutex end
    | _ -> Mutex.unlock irc_mutex in

Hashtbl.add functions "irc" irc;

start creator host_actor;
actors_display();
receive_handler();;
