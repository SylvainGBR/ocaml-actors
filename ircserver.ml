open Sys;;
open Unix;;
open ActorsType;;
open ActorsGlobal;;
open Actorssg;;

let irc_mutex = Mutex.create() in
let irc_on = ref false in
let irc_act = ref creator in

let irc_connections l =
  let connec = Hashtbl.create 13 in
  let ac = create() in
  Mutex.unlock irc_mutex;
  Hashtbl.add connec "server" ("server", ac);

  let rec irc_server() =
    let ircm (h, l) =
      let spread a b =
        match b with
          | ("server", _ ) -> (match l with
              | [S s; S g] -> Printf.printf "<%s> : %s \n%!" g s
              | _ -> failwith "Wrong Message Type Error in irc_connections");
          | ( s , a ) -> send a ("post", l) in
      match (h, l) with 
        | ("post", [S s; S st]) -> Hashtbl.iter spread connec; irc_server();
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
ignore (handle_unix_error Server.server ());;
actors_display();;
receive_handler();;
