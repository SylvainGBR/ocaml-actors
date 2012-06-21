open ActorsType

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

let (actors: (int, actor_env) Hashtbl.t) = Hashtbl.create 1313 (* Should probably be a weak hashtbl *)

let actors_display() =
  Printf.printf "Actors : ";
  let f a b c = Printf.printf "%n\n%!" a; c in
  Hashtbl.fold f actors ();;

let (nodes : (int, node) Hashtbl.t) = Hashtbl.create 97 
let n_mutex = Mutex.create()

let nodes_display() =
  Printf.printf "Nodes : ";
  let f a b c = Printf.printf "%n\n%!" a; c in
  Hashtbl.fold f nodes ();;

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

let (receive_scheduler : (actor * (message -> unit)) Queue.t) = Queue.create()
let rs_mutex = Mutex.create()

let (functions : (string, arg list -> unit) Hashtbl.t) = Hashtbl.create 97 

let nb_threads = ref 0
let active_threads = ref 0
let nb_threadmax = 5
let nbt_mutex = Mutex.create()

let receive_cond = Condition.create();;
let rc_mutex = Mutex.create();;

