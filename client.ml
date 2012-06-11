open Sys;;
open Unix;;
open ActorsType;;
open ActorsGlobal;;
open Actorssg;;

Printf.printf "Local Node : %n\n%!" local_node;
let ac = create() in
let nod = client Sys.argv.(1) in
nodes_display();
Printf.printf "Noeud distant : %n\n%!" nod.name;

let rec f a = 
  react (g a);
and g a m =
  match m with
    |("ping", [I i]) -> Printf.printf "Ping %n\n%!" i;
        send a ("pong", [I i]); f a;
    | _ -> Printf.printf "pas bon"; f a in

let aaac = create() in
let irct = create() in
Printf.printf "\nEnter your name : \n%!";
let pseudo = input_line (in_channel_of_descr stdin) in

let rec irc_talk rem = 
  let s = input_line (in_channel_of_descr stdin) in
  (* print_actor rem; Printf.printf "You Wrote : %s \n%!" s; *)
  send rem ("post", [S s; S pseudo]);
  irc_talk rem in

(* let rec funtest rem = *)
(*   let s = input_line (in_channel_of_descr stdin) in *)
(*   Printf.printf "You Wrote : %s \n%!" s;  *)
(*   print_actor rem; *)
(*   send rem ("post", [S s]); *)
(*   funtest rem in *)

let irc_connect() =

  let rec display() =
    let display_aux m =
      match m with 
        | ("post", [S s; S g]) -> Printf.printf "<%s> : %s \n%!" g s; display()
        | _ -> Printf.printf "Wrong return message %!"; print_message m; display() in
    react display_aux in

  let rec wait_validation m =
    match m with 
      | ("connected", (Actor a) :: q) -> Printf.printf "Connected ! \n%!";
          let _ = Thread.create irc_talk a in 
          (* let _ = Thread.create funtest a in Printf.printf "fdvfezgfdzf\n%!"; *)
          display()
      | _ -> react wait_validation

  in react wait_validation in

let rec test() =
  react gt;
and gt m =
  match m with
    |("retour", [S "bonjour"; Actor a]) -> Printf.printf "bonjour : ";
        print_actor a; send a ("bonjour", [S "siri"]); test();
    |("retour", [S "pipong"; Actor a]) -> Printf.printf "pipong : "; 
        print_actor a; start ac (fun () -> f a); send a ("pong", [I 0]); test();
    |("retour", [S "irc_connections"; Actor a]) -> send a ("join", [S pseudo; Actor irct]);
        start irct irc_connect; Printf.printf "Irc Server : %!"; print_actor a;
        test()
    | _ -> Printf.printf "Wrong return message "; print_message m; test() in

start aaac test;
(* start_remote "pipong" "127.0.0.1" nod.name aaac [Actor ac]; *)
(* start_remote "bonjour" "127.0.0.1" nod.name aaac []; *)
(* start_remote "irc_connections" "127.0.0.1" nod.name aaac []; *)
exec_remote "irc" "127.0.0.1" nod.name [Actor aaac];
receive_handler();;
