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

type actor_env = {actor: actor; sleeping : (message -> unit) Queue.t};;
let actors = Hashtbl.create 1313 (* Should probably be a weak hashtbl *)

(* let machines = Hashtbl.create 97 *)

let actors_id = ref 0
let a_mutex = Mutex.create()

let receive_scheduler = Queue.create()
let rs_mutex = Mutex.create()

let schedule_receive a f =
  Mutex.lock rs_mutex;
  Queue.add (a, f) receive_scheduler;
  Mutex.unlock rs_mutex;;

let awake aid =
  let a_env = Hashtbl.find actors aid in
  try 
    let f = Queue.pop a_env.sleeping in
    schedule_receive a_env.actor f
  with Queue.Empty -> ();;

let send a m =
  match a.actor_location with
    | Local lac -> begin Mutex.lock lac.mutex;
      Queue.add (mutables_copy m) lac.mailbox;
      Mutex.unlock lac.mutex; 
      awake a.actor_id end
    | Remote o -> ();;

exception React of (message -> unit);;

exception NotHandled;;

let execute a f =
  try f()
  with React g -> schedule_receive a g;;

let new_aid() =
  Mutex.lock a_mutex;
  incr actors_id;
  let i = !actors_id in
  begin Mutex.unlock a_mutex;
    i end;;

let create f =
  let i = new_aid() in
  let l_act = {mailbox = Queue.create() ; mutex = Mutex.create()} in
  let new_actor = {actor_id = i; actor_location = Local l_act} in
  let new_act_env = {actor = new_actor; sleeping = Queue.create()} in
  Hashtbl.add actors new_actor.actor_id new_act_env; 
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
        with Queue.Empty -> let a_env = Hashtbl.find actors a.actor_id in
                             Queue.add g a_env.sleeping;
      in
      reacting_aux(); end
    | Remote rac -> failwith "You cannot run a remote actor";;
  
let recieve_handler() = 
  try 
    let (a, f) = Queue.pop receive_scheduler in reacting a f;
  with Queue.Empty -> Thread.delay 0.01;;


(*val create : (actor -> unit) -> actor
val receive : actor -> (message -> unit) -> unit
val send : actor -> msg -> unit*)
