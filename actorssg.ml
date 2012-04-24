let debug = false;;

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

let mutex_lock mut =
  if debug then print_string "Locking. ";
  Mutex.lock mut;
  if debug then print_string "Locked. ";;

let mutex_unlock mut = 
  if debug then print_string "Unlocking. ";
  Mutex.unlock mut; 
  if debug then print_string "Unlocked. \n";;

let actors_id = ref 0
let a_mutex = Mutex.create()

let receive_scheduler = Queue.create()
let rs_mutex = Mutex.create()

let schedule_receive a f =
  if debug then print_string "In Schedule_receive : ";
  mutex_lock rs_mutex;
  Queue.add (a, f) receive_scheduler;
  mutex_unlock rs_mutex;;

let awake aid =
  if debug then print_string "In Awake : ";
  let a_env = Hashtbl.find actors aid in
  match a_env.actor.actor_location with
    | Local lac ->
        begin mutex_lock lac.mutex; 
          try
            let f = Queue.pop a_env.sleeping in
            begin schedule_receive a_env.actor f;
              mutex_unlock lac.mutex end
          with Queue.Empty -> mutex_unlock lac.mutex
        end
    | Remote o -> failwith "You cannot awake a remote actor";;

let send a m =
  match a.actor_location with
    | Local lac -> begin if debug then print_string "In Send : ";
      mutex_lock lac.mutex;
      Queue.add (mutables_copy m) lac.mailbox;
      mutex_unlock lac.mutex; 
      awake a.actor_id end
    | Remote o -> ();;

exception React of (message -> unit);;

exception NotHandled;;

let react f = raise (React f);;

let start a f =
  try f()
  with React g -> schedule_receive a g;;

let create() =
  let new_aid() =
    Mutex.lock a_mutex;
    incr actors_id;
    let i = !actors_id in
    begin Mutex.unlock a_mutex;
      i end in
  let id = new_aid() in
  let l_act = {mailbox = Queue.create() ; mutex = Mutex.create()} in
  let new_actor = {actor_id = id; actor_location = Local l_act} in
  let new_act_env = {actor = new_actor; sleeping = Queue.create()} in
  Hashtbl.add actors new_actor.actor_id new_act_env;
  new_actor;;

let reacting a g =
  match a.actor_location with
    | Local lac -> begin if debug then print_string "In Reacting : ";
      mutex_lock lac.mutex;
      let rec reacting_aux() = 
        try
          let m = Queue.pop lac.mailbox in
          try 
            mutex_unlock lac.mutex; g m;
          with 
            | React f -> begin print_newline();
              schedule_receive a f end
            | NotHandled ->  begin mutex_unlock lac.mutex;
              reacting_aux() end
        with Queue.Empty -> let a_env = Hashtbl.find actors a.actor_id in 
                            begin Queue.add g a_env.sleeping;
                              mutex_unlock lac.mutex end
      in reacting_aux() end
    | Remote rac -> failwith "You cannot run a remote actor";;
  
let rec recieve_handler() = 
  if debug then print_string "RH : number ";
  (try 
     let (a, f) = Queue.pop receive_scheduler in 
     begin  if debug then Printf.printf "%d \n" a.actor_id;
       reacting a f end
   with Queue.Empty -> Thread.delay 0.01);
  recieve_handler();;

let act1 = create() in
let act2 = create() in
let rec ping() =
  react pig
and pig m = 
  let (st1, l) = m in 
  if (st1 = "ping") then begin print_string "ping\n"; 
    send act2 ("pong", (I 1) :: []);
    ping() end in
let rec pong() =
  react pog
and pog m = 
  let (st2, l) = m in 
  if (st2 = "pong") then begin print_string "pong\n"; 
    send act1 ("ping", (I 1) :: []);
    pong() end in begin
      start act1 ping;
      start act2 pong;
      send act1 ("ping", (I 1) :: []);
      recieve_handler();
    end;;
