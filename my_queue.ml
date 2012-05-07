  type 'a t = ('a list * 'a list) ref
  exception Empty
  let create () = ref ([], [])
    
  let add x queue =
    let front, back = !queue in
    queue := (x::front, back)

  let push x queue =
    let front, back = !queue in
    queue := (front, x::back)
      
  let rec take queue =
    match !queue with
        (front, x :: back) ->
          queue := (front, back);
          x
      | ([], []) ->    
          raise Empty
      | (front, []) ->
          queue := ([], List.rev front);
          take queue

