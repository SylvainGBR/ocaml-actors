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

let treat_connect i o clientset =
  let s = input_value i in
  mutex_lock n_mutex;
  if (Hashtbl.mem nodes s) then begin Printf.printf "This node already exists\n%!"; close_out o;
    mutex_unlock n_mutex end
  else begin output_value o local_node;
    flush o;
    let ac = create() in
    let t = Thread.create receive_remote (i, s) in
    let hst = {name = s; agent = ac; support = t} in
    Hashtbl.add nodes s hst;
    start ac (fun() -> sender o);
    actors_display();
    nodes_display();
    Printf.printf "Noeud distant : %n\n%!" hst.name end;
  mutex_unlock n_mutex;;

let rec restart_on_EINTR f x =
  try f x with Unix.Unix_error (Unix.EINTR, _, _) -> restart_on_EINTR f x;;
    
let install_tcp_server_socket addr =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  try
    Unix.bind s addr;
    Unix.listen s 10;
    s
  with z -> Unix.close s; raise z;;

let tcp_server treat_connection addr =
  let rec run s =
    let clientset = restart_on_EINTR Unix.accept s in
    let _ = Thread.create treat_connection clientset in
    run s in
  ignore (Sys.signal Sys.sigpipe Sys.Signal_ignore);
  let server_sock = install_tcp_server_socket addr in
  run server_sock;;

let server () =
  Printf.printf "Local Node : %n\n%!" local_node;
  let port = 4242 in
  Printf.printf "%s\n%!" (string_of_inet_addr ((gethostbyname(gethostname())).h_addr_list.(0)));
     (* let host = (gethostbyname(gethostname())).h_addr_list.(0) in *)
  (* let host = (gethostbyname "127.0.0.1").h_addr_list.(0) in *)
  let host = (gethostbyname "193.55.250.232").h_addr_list.(0) in
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

(* let _ = handle_unix_error server () in *)
Hashtbl.add functions "bonjour" bonjour ;;

let rec pipong l = 
  let gs ar m =
    match (ar, m) with
      |(Actor a, ("pong", [I i])) -> Printf.printf "Pong %n\n%!" i; 
          send a ("ping", [I (i+1)]);
          pipong [ar];
      |( x , ("pong", [I i])) -> Printf.printf "Invalid Argument"
      | ( _ , (s, _)) -> Printf.printf "pas bon : %s\n%!" s; pipong [ar] in
  react (gs (List.hd l)) in

Hashtbl.add functions "pipong" pipong;;
