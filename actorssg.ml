let debug_flag = ref false
let debug fmt =
  if !debug_flag then Printf.eprintf fmt
  else Printf.ifprintf stderr fmt
    
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
  actor_host : string; (* uniq identifier of the machine on which it was created (20-byte string generated randomly at startup) *)
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

let local_machine = Unix.gethostname()

let local_to_remote a =
match a.actor_location with
  | Local lac -> let rma = {actor_host = local_machine} in
 {actor_id = a.actor_id; actor_location = Remote rma}
  | Remote rma -> a;;

type actor_env = {actor: actor; sleeping : (message -> unit) Queue.t}
let actors = Hashtbl.create 1313 (* Should probably be a weak hashtbl *)
  
type machine = {
  name : string;
  inc : in_channel;
  out : out_channel;
}
let machines = Hashtbl.create 97 

exception IncorrectMessage;;

let actors_update_send m =
  let rec actors_update_aux l =
    match l with
      | [] -> [];
      | (Actor a) :: q -> (match a.actor_location with
          | Local lac -> let rml = {actor_host = local_machine} in
                         (Actor {actor_id = a.actor_id; actor_location = Remote rml}) :: (actors_update_aux q);
          | Remote rma -> (Actor a) :: (actors_update_aux q););
      | t :: q -> t :: (actors_update_aux q) in
  let (s, l) = m in (s, actors_update_aux l);;
          
let actors_update_receive m =
  let rec actors_update_aux l =
    match l with
      | [] -> [];
      | (Actor a) :: q -> (match a.actor_location with
          | Remote rma -> if rma.actor_host = local_machine then  
              (try let aenv = Hashtbl.find actors a.actor_id in
                   (Actor aenv.actor) :: (actors_update_aux q);
               with Not_found -> debug "The actor number %n doesn't exist\n%!" a.actor_id;
                 raise IncorrectMessage)
            else (Actor a) :: (actors_update_aux q);             
          | Local lac -> debug "The actor number %n is local!%!" a.actor_id;
              raise IncorrectMessage);
      | t :: q -> t :: (actors_update_aux q) in
  let (s, l) = m in (s, actors_update_aux l);;

let mutex_lock mut =
  debug "Locking. %!";
  Mutex.lock mut;
  debug "Locked. %!";;

let mutex_unlock mut = 
  debug "Unlocking. %!";
  Mutex.unlock mut; 
  debug "Unlocked. \n%!";;

let actors_id = ref 0
let a_mutex = Mutex.create()

let receive_scheduler = Queue.create()
let rs_mutex = Mutex.create()

let schedule_receive a f =
  debug "In Schedule_receive : %!";
  mutex_lock rs_mutex;
  Queue.add (a, f) receive_scheduler;
  mutex_unlock rs_mutex;;

let awake aid =
  debug "In Awake : %!";
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

type netdata = {
  to_actor : actor;
  msg : message;
}

let send a m =
  match a.actor_location with
    | Local lac -> begin debug "In Send : %!";
      mutex_lock lac.mutex;
      My_queue.add m lac.mailbox;
      mutex_unlock lac.mutex; 
      awake a.actor_id end
    | Remote rma -> let rmm = (try Hashtbl.find machines rma.actor_host 
      with Not_found -> try let host = Unix.gethostbyname rma.actor_host in 
                            let (i, o) = Unix.open_connection (Unix.ADDR_INET (host.Unix.h_addr_list.(0), 80)) in
                            let hst = {name = rma.actor_host; inc = i; out = o} in
                            Hashtbl.add machines rma.actor_host hst;
                            hst;
        with Not_found -> failwith "Wrong machine name") in
                    output_value rmm.out (actors_update_send m);
                    flush rmm.out;;

exception React of (message -> unit);;

exception NotHandled;;

let react f = raise (React f);;

let start a f =
 debug "Starting Actor %d \n%!" a.actor_id;
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
  let l_act = {mailbox = My_queue.create() ; mutex = Mutex.create()} in
  let new_actor = {actor_id = id; actor_location = Local l_act} in
  let new_act_env = {actor = new_actor; sleeping = Queue.create()} in
  Hashtbl.add actors new_actor.actor_id new_act_env;
  new_actor;;

let reacting a g =
  match a.actor_location with
    | Local lac -> begin debug "In Reacting : %!";
      let rec reacting_aux() = 
        mutex_lock lac.mutex;
        try
          let m = My_queue.take lac.mailbox in
          try 
            mutex_unlock lac.mutex; g m
          with 
            | React f -> schedule_receive a f;
            | NotHandled -> begin reacting_aux();
              mutex_lock lac.mutex;
              My_queue.push m lac.mailbox;
              mutex_unlock lac.mutex end
        with My_queue.Empty -> let a_env = Hashtbl.find actors a.actor_id in begin
          Queue.add g a_env.sleeping; mutex_unlock lac.mutex end
      in reacting_aux() end
    | Remote rac -> failwith "You cannot run a remote actor";;

let rec receive_remote i =
  debug "In receive_remote : %!";
  let ndat = input_value i in
  if ndat.to_actor.actor_id = 0 then () (*Changer*)
  else (try let aenv = Hashtbl.find actors ndat.to_actor.actor_id in
            match aenv.actor.actor_location with
              | Local lac -> send aenv.actor (actors_update_receive ndat.msg)
              | Remote rma -> debug "The actors table is not supposed to have remote actors"
    with Not_found -> debug "The actor number %n doesn't exist\n%!" ndat.to_actor.actor_id);
  receive_remote i;;

let rec receive_handler() = 
  debug "RH : number %!";
  let cont = ref true in begin
    (try 
      let (a, f) = Queue.pop receive_scheduler in 
      begin debug "%d \n%!" a.actor_id;
        reacting a f; end
    with Queue.Empty -> let f a b c = c + Queue.length b.sleeping in 
                        let att = Hashtbl.fold f actors 0 in
                        if att = 0 then begin debug "\n Finex.\n%!"; cont := false end
                        else begin Thread.delay 0.01;
                          debug " En attente : %d \n%!" (Hashtbl.fold f actors 0) end);
    if (!cont) then receive_handler() end;;
