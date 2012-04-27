let debug = true
(* let debug_flag = ref false *)
(* let debug fmt = *)
(*   if !debug_flag then Printf.eprintf fmt *)
(*   else Printf.ifprintf stderr fmt *)
    
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
      My_queue.add (mutables_copy m) lac.mailbox;
      mutex_unlock lac.mutex; 
      awake a.actor_id end
    | Remote o -> ();;

exception React of (message -> unit);;

exception NotHandled;;

let react f = raise (React f);;

let start a f =
  if debug then Printf.printf "Starting Actor %d \n%!" a.actor_id;
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
    | Local lac -> begin if debug then print_string "In Reacting : ";
      mutex_lock lac.mutex;
      let rec reacting_aux() = 
        try
          let m = My_queue.take lac.mailbox in
          try 
            g m; mutex_unlock lac.mutex;
          with 
            | React f -> schedule_receive a f ;
            | NotHandled -> begin reacting_aux();
              My_queue.push m lac.mailbox end
        with My_queue.Empty -> let a_env = Hashtbl.find actors a.actor_id in 
                               Queue.add g a_env.sleeping;
      in reacting_aux(); mutex_unlock lac.mutex end
    | Remote rac -> failwith "You cannot run a remote actor";;

let rec receive_handler() = 
  if debug then print_string "RH : number ";
  let cont = ref true in begin
    (try 
      let (a, f) = Queue.pop receive_scheduler in 
      begin (if debug then Printf.printf "%d \n%!" a.actor_id);
        reacting a f; end
    with Queue.Empty -> let f a b c = c + Queue.length b.sleeping in 
                        let att = Hashtbl.fold f actors 0 in
                        if att = 0 then begin (if debug then print_string "\n Finex.\n%!"); cont := false end
                        else begin Thread.delay 0.01;
                          if debug then Printf.printf " En attente : %d \n%!" (Hashtbl.fold f actors 0) end);
    if (!cont) then receive_handler() end;;

let ping_pong() =
  let act1 = create() in
  let act2 = create() in
  let rec ping() =
    react pig
  and pig m = 
    let (s, l) = m in 
    if (s = "ping") then begin print_string "ping"; 
      (match l with 
        | (Actor a) :: (I i) :: q ->  Printf.printf " : %d\n%!" i;
            send a ("pong", (Actor act1) :: (I (i + 1)) :: []);
        | _ -> raise NotHandled) ;
      ping() end in
  let rec pong() =
    react pog
  and pog m = 
    let (s, l) = m in 
    if (s = "pong") then begin print_string "pong"; 
      (match l with 
        | (Actor a) :: (I i) :: q ->  Printf.printf " : %d\n%!" i;
            send a ("ping", (Actor act2) :: (I (i + 1)) :: []);
            (* send a ("ping", (Actor act1) :: (I (i + 1)) :: []); *)
        | _ -> raise NotHandled) ;
      pong() end
  in begin
    start act1 ping;
    start act2 pong;
    (* start act1 pong; *)
    send act1 ("ping", (Actor act2) :: (I 1) :: []);
    (* send act1 ("ping", (Actor act1) :: (I 1) :: []); *)
    receive_handler();
  end;;

ping_pong();;

let calcul_pi n s =
  let t = Sys.time() in
  let main_act = create() in
  let slave() =
    let slv m =
      let (str, l) = m in
      match l with
        | (Actor a) :: (I k) :: (I n) :: (I s) :: q -> let res = ref 0.0 in begin
          for i = k * n / s + 1 to (k + 1) * n / s do
            let r = (float_of_int i -. 0.5) /. float_of_int n in
            res := (!res) +. 1. /. (1. +. r *. r);
          done;
          send a ("pi", (F (!res)) :: []) end
        | _ -> raise NotHandled 
    in
    react slv
  in 
  let master() =
    let compteur = ref 1 in
    let res = ref 0.0 in
    let rec act() =
      react  mlisten
    and mlisten m =
      let (str, l) = m in
      match l with
        | (F r) :: q -> res := (!res) +. r;
            if (!compteur = s) then Printf.printf "*** %f ***\n %!"  (4. *. !res /. float_of_int n) 
            else begin if debug then begin print_string "Recu "; print_int (!compteur) end;
              incr compteur; 
              act() end;
        | _ -> raise NotHandled
    in act()
  in 
  start main_act master;
  for k = 0 to s-1 do 
    let ac = create() in begin
    start ac slave;
    send ac ("pi", (Actor main_act) :: (I k) :: (I n) :: (I s) :: []);
    if debug then Printf.printf "Sent pi_request to %d \n %!" k
    end
  done;
  receive_handler();
  Printf.printf "*** Time : %f ***\n %!" (Sys.time() -. t);;

(* calcul_pi 30000000 100000;; *)
