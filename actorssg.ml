open Actors

let debug_flag = ref false
let debug fmt =
  if !debug_flag then Printf.eprintf fmt
  else Printf.ifprintf stderr fmt;;

let mutex_debug_flag = ref false
let mutex_debug fmt =
  if !mutex_debug_flag then Printf.eprintf fmt
  else Printf.ifprintf stderr fmt;;

Random.init (int_of_float (Unix.time()));;
let local_node = Random.int 1024;;
let local_machine = Unix.gethostname();;

type actor_env = {actor: actor; sleeping : (message -> unit) Queue.t}

let actors = Hashtbl.create 1313 (* Should probably be a weak hashtbl *)

let actors_display() = 
  Printf.printf "Actors : ";
  let f a b c = Printf.printf "%n\n%!" a; c in
  Hashtbl.fold f actors ();;
  
type node = {
  name : int;
  agent : actor;
  support : Thread.t;
}
let nodes = Hashtbl.create 97 
let n_mutex = Mutex.create()

let nodes_display() = 
  Printf.printf "Nodes : ";
  let f a b c = Printf.printf "%n\n%!" a; c in
  Hashtbl.fold f nodes ();;

exception IncorrectMessage;;

let mutex_lock mut =
  mutex_debug "Locking. %!";
  Mutex.lock mut;
  mutex_debug "Locked. %!";;

let mutex_unlock mut = 
  mutex_debug "Unlocking. %!";
  Mutex.unlock mut; 
  mutex_debug "Unlocked. \n%!";;

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
  to_actor : int;
  msg : message;
}

exception React of (message -> unit);;

let react f = raise (React f);;

exception NotHandled;;

let start a f =
 debug "Starting Actor %d \n%!" a.actor_id;
  try f()
  with React g -> schedule_receive a g;;

let create() =
  let new_aid() =
    Mutex.lock a_mutex;
    let i = !actors_id in begin
      incr actors_id;
      Mutex.unlock a_mutex;
      i end in
  let id = new_aid() in
  let l_act = {mailbox = My_queue.create() ; mutex = Mutex.create()} in
  let new_actor = {actor_id = id; actor_location = Local l_act} in
  let new_act_env = {actor = new_actor; sleeping = Queue.create()} in
  Hashtbl.add actors new_actor.actor_id new_act_env;
  new_actor;;

let creator = create();;

let actors_update_send i (st, li) =
  let rec actors_update_aux l =
    match l with
      | [] -> [];
      | (Actor a) :: q -> (match a.actor_location with
          | Local lac -> let rml = {actor_host = local_machine; actor_node = local_node} in
                         (Actor {actor_id = a.actor_id; actor_location = Remote rml}) :: (actors_update_aux q);
          | Remote rma -> (Actor a) :: (actors_update_aux q););
      | t :: q -> t :: (actors_update_aux q) in
  ("send", (I i) :: (S st) :: (actors_update_aux li));;
          
let actors_update_receive m =
  let rec actors_update_aux l =
    match l with
      | [] -> [];
      | (Actor a) :: q -> (match a.actor_location with
          | Remote rma -> if rma.actor_node = local_node then  
              (try let aenv = Hashtbl.find actors a.actor_id in
                   (Actor aenv.actor) :: (actors_update_aux q);
               with Not_found -> debug "The actor number %n doesn't exist\n%!" a.actor_id;
                 raise IncorrectMessage)
            else (Actor a) :: (actors_update_aux q);             
          | Local lac -> debug "The actor number %n is local!%!" a.actor_id;
              raise IncorrectMessage);
      | t :: q -> t :: (actors_update_aux q) in
  let (s, l) = m in (s, actors_update_aux l);;

let rec sender o =
  let snd m = 
    match m with
      | ("send", (I i) :: (S s) :: l) -> let d =  {to_actor = i; msg = (s, l)} in
                                         output_value o d;
                                         debug "Sending a %s message to the remote actor %n\n%!" s i;
                                         flush o;
                                         sender o;
      | _ ->  Printf.printf "Wrong Message in sender : "; print_message m; raise NotHandled in
  react snd;;

let rec send a m =
  match a.actor_location with
    | Local lac -> begin debug "Sending to the local actor %n : %!" a.actor_id;
      mutex_lock lac.mutex;
      My_queue.add m lac.mailbox;
      mutex_unlock lac.mutex; 
      awake a.actor_id end
    | Remote rma -> debug "Sending to the remote actor %n from %s %n %!" a.actor_id rma.actor_host rma.actor_node; 
        let rmn = (try Hashtbl.find nodes rma.actor_node 
          with Not_found -> try let host = Unix.gethostbyname rma.actor_host in 
                                client host.Unix.h_name;
            with Not_found -> failwith "Wrong machine name") in
        debug "through Local actor %n\n%!" rmn.agent.actor_id;
        send rmn.agent (actors_update_send a.actor_id m)
and receive_remote (i, server_name) =
  debug "In receive_remote : %!";
  (try (let ndat = input_value i in
  (try let aenv = Hashtbl.find actors ndat.to_actor in
       match aenv.actor.actor_location with
         | Local lac -> send aenv.actor (actors_update_receive ndat.msg);
         | Remote rma -> debug "The actors table is not supposed to have remote actors"
   with Not_found -> Printf.printf "The actor number %n doesn't exist\n%!" ndat.to_actor); receive_remote (i, server_name))
  with (End_of_file) -> Printf.printf "Connexion Interrupted with %n\n%!" server_name;)
and client_aux server_name =
  let port_number = 4242 in
  let server_addr =
    try (Unix.gethostbyname server_name).Unix.h_addr_list.(0)
    with Not_found ->
      prerr_endline (server_name ^ ": Host not found");
      exit 2 in
  Unix.open_connection (Unix.ADDR_INET(server_addr, port_number))
and client server_name =
  let (i, o) = Unix.handle_unix_error client_aux server_name in
  output_value o local_node;
  flush o;
  let rmn = input_value i in
  let ac = create() in
  let t = Thread.create receive_remote (i, rmn) in
  let hst = {name = rmn; agent = ac; support = t} in
  (* mutex_lock n_mutex; *)
  Hashtbl.add nodes rmn hst;
  (* mutex_unlock n_mutex; *)
  start ac (fun() -> sender o);
  hst;;

let functions = Hashtbl.create 97 

let rec host_actor() =
  react ca
and ca m =
  match m with
    | ("start", (S s) :: (Actor a) :: q) -> (try let f = Hashtbl.find functions s in
                                                 let ac = create() in 
                                                 Printf.printf "Creating actor number %n (%s) with host_actor\n%!" ac.actor_id s;
                                                 start ac (fun () -> f q); 
                                                 send a ("retour", [S s; Actor ac]); host_actor();
      with Not_found -> Printf.printf "This function does not exist");
        host_actor();
    | (s, q) -> (try let f = Hashtbl.find functions s in 
                     Printf.printf "Executing function (%s) \n%!" s;
                     f q; host_actor()
      with Not_found -> Printf.printf "This function does not exist"; host_actor());;

let start_remote s h n ac argm =
let rac = {actor_id = 0; actor_location = Remote {actor_host = h; actor_node = n}} in send rac ("start", (S s) :: (Actor ac) :: argm);;

let exec_remote s h n argm =
let rac = {actor_id = 0; actor_location = Remote {actor_host = h; actor_node = n}} in send rac (s, argm);;

let reacting a g =
  debug "In Reacting (actor %n): %!" a.actor_id;
  match a.actor_location with
    | Local lac ->
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
        in reacting_aux()
    | Remote rac -> failwith "You cannot run a remote actor";;

let rec receive_handler() = 
  (* debug "RH : number %!"; *)
  let cont = ref true in begin
    (try 
      let (a, f) = Queue.pop receive_scheduler in 
      begin (* debug "%d \n%!" a.actor_id; *)
        reacting a f; end
    with Queue.Empty -> let f a b c = c + Queue.length b.sleeping in 
                        let att = Hashtbl.fold f actors 0 in
                        if att = 0 then begin debug "\n Finex.\n%!"; cont := false end
                        else begin  Thread.delay 0.0001; 
                          (* debug " En attente : %d \n%!" (Hashtbl.fold f actors 0) end*) end); 
    if (!cont) then receive_handler() end;;
