(*
 * Copyright (C) Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

type t (** a valid packet *)

module Op : sig
  type t =
    | Debug | Directory | Read | Getperms
    | Watch | Unwatch | Transaction_start
    | Transaction_end | Introduce | Release
    | Getdomainpath | Write | Mkdir | Rm
    | Setperms | Watchevent | Error | Isintroduced
    | Resume | Set_target
	| Restrict
  (** The type of xenstore operation *)

  val to_string: t -> string

  val of_int32: int32 -> t option
  val to_int32: t -> int32
end

module ACL : sig
    (** Access control lists *)

  type perm =
    | NONE
    | READ
    | WRITE
    | RDWR

  val char_of_perm: perm -> char

  val perm_of_char: char -> perm option

  type domid = int

  type t = {
	  owner: domid;             (** domain which "owns", has full access *)
	  other: perm;              (** default permissions for all others... *)
	  acl: (domid * perm) list; (** ... unless overridden in the ACL *)
  }

  val of_string: string -> t option

  val to_string: t -> string

end

module Parser : sig
  (** Incrementally parse packets *)

  type state =
    | Unknown_operation of int32 (** received an unexpected message type *)
    | Parser_failed              (** we failed to parse a header *)
    | Need_more_data of int      (** we still need 'n' bytes *)
    | Packet of t                (** successfully decoded a packet *)

  type parse (** the internal state of the parser *)

  val start: unit -> parse
  (** create a parser set to the initial state *)

  val state: parse -> state
  (** query the state of the parser *)

  val input: parse -> string -> parse
  (** input some bytes into the parser. Must be no more than needed
      (see Need_more_data above) *)
end

module type CHANNEL = sig
  type t
  val read: t -> string -> int -> int -> int Lwt.t
  val write: t -> string -> int -> int -> int Lwt.t
end

exception Unknown_xenstore_operation of int32
exception Response_parser_failed

module PacketStream : functor(C: CHANNEL) -> sig
  type stream
  val make: C.t -> stream
  val recv: stream -> t Lwt.t
  val send: stream -> t -> unit Lwt.t
end

val to_string : t -> string
val get_tid : t -> int32
val get_ty : t -> Op.t
val get_data : t -> string
val get_rid : t -> int32

val create : int32 -> int32 -> Op.t -> string -> t

module Token : sig
  type t
  (** A token is associated with every watch and returned in the callback *)

  val to_debug_string: t -> string
  (** [to_string token] returns a debug-printable version of [token] *)

  val of_user_string: string -> t
  (** [of_user_string x] transforms [x] into a fresh watch token *)

  val to_user_string: t -> string
  (** [to_user_string token] returns the user-supplied part of [token] *)

  val of_string: string -> t
  (** [of_string x] parses the marshalled token [x] *)
end

module Response : sig
  val read : t -> string -> t
  val getperms : t -> ACL.t -> t
  val getdomainpath : t -> string -> t
  val transaction_start : t -> int32 -> t
  val directory : t -> string list -> t
  val write : t -> t
  val mkdir : t -> t
  val rm : t -> t
  val setperms : t -> t
  val watch : t -> t
  val unwatch : t -> t
  val transaction_end : t -> t
  val introduce : t -> t
  val release : t -> t
  val error : t -> string -> t
  val debug : t -> string list -> t
  val set_target : t -> t
  val restrict : t -> t
  val resume : t -> t
  val isintroduced : t -> bool -> t
end

module Request : sig
  val directory : string -> int32 -> t option
  val read : string -> int32 -> t option
  val getperms : string -> int32 -> t option
  val rm : string -> int32 -> t option
  val setperms : string -> ACL.t -> int32 -> t option
  val write : string -> string -> int32 -> t option
  val mkdir : string -> int32 -> t option

  val transaction_start : unit -> t option
  val transaction_end : bool -> int32 -> t option
  val introduce : int -> nativeint -> int -> t option
  val release : int -> t option
  val resume : int -> t option
  val getdomainpath : int -> t option
  val watch : string -> Token.t -> t option
  val unwatch : string -> Token.t -> t option
  val debug : string list -> t option
  val set_target : int -> int -> t option
  val restrict : int -> t option
  val isintroduced : int -> t option

  type payload =
  | Read of string
  | Directory of string
  | Getperms of string
  | Getdomainpath of int
  | Transaction_start
  | Write of string * string
  | Mkdir of string
  | Rm of string
  | Setperms of string * ACL.t
  | Watch of string * string
  | Unwatch of string * string
  | Transaction_end of bool
  | Debug of string list
  | Introduce of int * Nativeint.t * int
  | Resume of int
  | Release of int
  | Set_target of int * int
  | Restrict of int
  | Isintroduced of int
  | Error of string
  | Watchevent of string

  val parse: t -> payload option
end

module Unmarshal : sig
  val string : t -> string option
  val list : t -> string list option
  val acl : t -> ACL.t option
  val int : t -> int option
  val int32 : t -> int32 option
  val unit : t -> unit option
  val ok : t -> unit option
end

exception Enoent of string (** named key does not exist *)
exception Eagain           (** transaction must be repeated *)
exception Invalid
exception Error of string  (** generic catch-all error *)

val response: string -> t -> t -> (t -> 'a option) -> 'a
(** [response debug_hint sent received unmarshal] returns the unmarshalled
    response corresponding to the [received] packet relative to the [sent]
    packet *)
