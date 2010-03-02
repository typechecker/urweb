type t = string

val str : char -> t

val length : t -> int

val append : t -> t -> t

val sub : t -> int -> char
val suffix : t -> int -> string

val index : t -> char -> option int
val atFirst : t -> char -> option string

val mindex : {Haystack : t, Needle : t} -> option int

val substring : t -> {Start : int, Len : int} -> string

val split : t -> char -> option (string * string)
val msplit : {Haystack : t, Needle : t} -> option (string * char * string)

val all : (char -> bool) -> string -> bool
val mp : (char -> char) -> string -> string

val newlines : ctx ::: {Unit} -> [[Body] ~ ctx] => string -> xml ([Body] ++ ctx) [] []

val isPrefix : {Full : t, Prefix : t} -> bool
