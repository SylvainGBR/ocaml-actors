open ActorsType
open ActorsGlobal
open Actorssg

let ping_pong() =
  let act1 = create() in
  let act2 = create() in
  let rec ping() =
    react pig
  and pig m = 
    let (s, l) = m in
    if (s = "ping") then begin Printf.printf "ping"; 
      (match l with 
        | (Actor a) :: (I i) :: q ->  Printf.printf " : %d\n%!" i;
            send a ("pong", (Actor act1) :: (I (i + 1)) :: []);
        | _ -> raise NotHandled) ;
      ping() end 
    else raise NotHandled
  in
  let rec pong() =
    react pog
  and pog m = 
    let (s, l) = m in
    if (s = "pong") then begin Printf.printf "pong"; 
      (match l with 
        | (Actor a) :: (I i) :: q ->  Printf.printf " : %n\n%!" i;
            (* Printf.printf "Threads : %n\n%!" (!nb_threads); *)
            send a ("ping", (Actor act2) :: (I (i + 1)) :: []);
            (* send a ("ping", (Actor act1) :: (I (i + 1)) :: []); *)
        | _ -> raise NotHandled) ;
      pong() end
    else raise NotHandled
  in begin
    start act1 ping;
    start act2 pong;
    (* start act1 pong; *)
    send act1 ("ping", (Actor act2) :: (I 1) :: []);
    (* send act1 ("ping", (Actor act1) :: (I 1) :: []); *)
    receive_handler();
  end;;

(* ping_pong();; *)

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
            if (!compteur = s) then Printf.printf "*** Actors : %f ***\n %!"  (4. *. !res /. float_of_int n) 
            else begin debug "Recu %d%!" (!compteur);
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
    debug "Sent pi_request to %d \n %!" k
    end
  done;
  receive_handler();
  Printf.printf "*** Time : %f ***\n %!" (Sys.time() -. t);;

calcul_pi 30000000 100;;

let calcul_picpu n =
  let t = Sys.time() in
  let res = ref 0.0 in
  for i = 1 to n do
    let r = (float_of_int i -. 0.5) /. float_of_int n in
    res := (!res) +. 1. /. (1. +. r *. r)
  done;
  Printf.printf "*** CPU : %f ***\n%!" (4. *. !res /. float_of_int n);
  Printf.printf "*** Time : %f ***\n %!" (Sys.time() -. t);;

calcul_picpu 30000000;;
