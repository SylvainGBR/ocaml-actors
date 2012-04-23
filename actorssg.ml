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
  mailbox : message Queue.t;
  mutex : Mutex.t;
 (* handler : (message -> unit);*)
}

and remote_actor = {
  actor_host : string; (* uniq identifier of the machine on which it was created (20-byte string generated randomly at startup) *)
  remote_ip : string;
  remote_port : int;
}

and location =
  | Local of local_actor
  | Remote of remote_actor
      
and actor = {
  actor_id : int; (* local number of the actor when it was created *)
  actor_location : location;
}

let mutables_copy (s, al) = 
  let rec mutables_copy_aux_d (str, argt) =
    (str, mutables_copy_aux argt)
  and mutables_copy_aux argt =
    match argt with
      | A a -> A (Array.copy a);
      | AC ac -> AC (Array.copy ac);
      | AS ast -> AS (Array.copy ast);
      | AI ai -> AI (Array.copy ai);
      | AF af -> AF (Array.copy af);
      | L [] -> L [];
      | L l -> L (List.map mutables_copy_aux l);
      | D [] -> D [];
      | D l -> D (List.map mutables_copy_aux_d l);
      | _ -> argt in
  (s, List.map mutables_copy_aux al);;

let actors = Hashtbl.create 1313 (* Should probably be a weak hashtbl *)

(* let machines = Hashtbl.create 97 *)

let actors_id = ref 0
let a_mutex = Mutex.create()

let receive_scheduler = Queue.create()

let send a m =
  match a.actor_location with
    | Local lac -> begin Mutex.lock lac.mutex; Queue.add (mutables_copy m) lac.mailbox; Mutex.unlock lac.mutex end
    | Remote o -> ();;

let schedule_receive a f =
Queue.add (a, f) receive_scheduler;;


exception React of (message -> unit);;

exception NotHandled;;

let execute a f =
  try f()
  with React g -> schedule_receive a g;;

let create f =
  incr actors_id;
  let l_act = {mailbox = Queue.create() ; mutex = Mutex.create()} in
  let new_actor = {actor_id = !actors_id; actor_location = Local l_act} in
  Hashtbl.add actors new_actor new_actor.actor_id;
  execute new_actor f;
  new_actor;;

let rec reacting a g =
  match a.actor_location with
    | Local lac -> begin Mutex.lock lac.mutex;
      let rec reacting_aux() = 
        try
          let m = Queue.pop lac.mailbox in
          try (g m)
          with 
            | React f -> begin  Mutex.unlock lac.mutex;
                reacting a f end
            | NotHandled -> reacting_aux();
        with Queue.Empty -> ();
      in
      reacting_aux(); end
    | Remote rac -> failwith "You cannot run a remote actor";;
  

(*val create : (actor -> unit) -> actor
val receive : actor -> (message -> unit) -> unit
val send : actor -> msg -> unit*)
