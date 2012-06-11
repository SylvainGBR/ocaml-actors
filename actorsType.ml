type arg =
  | Actor of actor

  | C of char
  | S of string 
  | I of int
  | F of float

  | L of arg list
  | A of arg array
  | D of (string * arg) list

  | LC of char list
  | LS of string list
  | LI of int list
  | LF of float list 

  | AC of char array
  | AS of string array
  | AI of int array
  | AF of float array

and message = string * arg list

and local_actor = {
  mailbox : message My_queue.t;
  mutex : Mutex.t;
}

and remote_actor = {
  actor_host : string;
  actor_node : int; (* uniq identifier of the machine on which it was created (20-byte string generated randomly at startup) *)
  (* remote_ip : string; *)
  (* remote_port : int; *)
}
    
and location =
  | Local of local_actor
  | Remote of remote_actor
      
and actor = {
  actor_id : int; (* local number of the actor when it was created *)
  actor_location : location;
}

type actor_env = {actor: actor; sleeping : (message -> unit) Queue.t}

type node = {
  name : int;
  agent : actor;
  support : Thread.t;
}

type netdata = {
  to_actor : int;
  msg : message;
}

exception React of (message -> unit);;

exception IncorrectMessage;;


let print_actor a =
  match a.actor_location with
    | Local lac -> Printf.printf "Local %n; \n%!" a.actor_id;
    | Remote rma -> Printf.printf "Remote %s %n %n; \n%!" rma.actor_host rma.actor_node a.actor_id;;

let print_message (st, li) =
  Printf.printf "( %s, " st;
  Printf.printf "[";
  let rec print_arg_list al =
    match al with
      | [] -> Printf.printf "])\n%!";
      | (Actor a) :: q -> print_actor a; print_arg_list q;
      | (C c) :: q -> Printf.printf "C %c; " c; print_arg_list q;
      | (S s) :: q -> Printf.printf "S %s; " s; print_arg_list q;
      | (I i) :: q -> Printf.printf "I %n; " i; print_arg_list q;
      | (F f) :: q -> Printf.printf "F %f; " f; print_arg_list q;
      |  _ :: q -> Printf.printf "***; ";  print_arg_list q in
  print_arg_list li;;
