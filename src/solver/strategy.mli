(**
  This module provides utilities to define new resolution strategies.
  We introduce a monad [('env, 'res) Strategy.t] to build custom solvers.

  Intuitively, a value of type [('env, 'res) Strategy.t] is a function from ['env -> 'res]
  where ['env] is the type of resolution contexts and ['res] is the result of the strategy.

  A strategy may or may not return a valid result. To modelize this situation, the stragegies results are
  wrapped in the the [('env, 'res) status] type in order to give additional
  information on strategies executions.

  The call [run s e] executes the strategy [s] in context [e] and return a status information.
*)

type ('env, 'res) status =
  | Abort of string
  | Contradict
  | Update of 'env
  | UpdateValue of 'env * 'res
  | Value of 'res
(**
  Status message reported by strategies.
  The status is either:
  {ul
    {- A failure with a message indicating an early interuption of the strategy }
    {- A contraidiction notification : a contradiction has been found in the current environment }
    {- A value indicating that the strategy successfully computed a result }
    {- An update notification indicating that the strategy is not done but
      has found some information to enrich the resolution context }
    {- An update notification together with an intermediate value.
      This indicate that the strategy computed an intermediate value [v]
      and updated the context. It is especially useful to compose intermediate steps.
    }
  }
*)

type ('env, 'res) t

val return : 'res -> ('env, 'res) t
(** [return v] is a trivial strategy always returning [v] *)

val abort : string -> ('env, 'res) t
(** [abort err] is a trivial strategy always failing with error message [err] *)

val contradict : ('env, 'res) t
(** [contradict] is a strategy reporting that a contradiction has been found in context *)

val skip : ('env, 'res) t
(** a strategy doing litteraly nothing. It returns an update notification
    but the environment thus provided is unchanged.
*)

val update : ('env -> 'env) -> ('env, 'res) t
(**
  [update f] is a strategy applying function [f] to its current environment and 
  returning the corresponding update notification
*)

val update_ret : 'res -> ('env -> 'env) -> ('env, 'res) t
(**
  [update_ret f v] is similar to [update v] but also returns the
  intermediate value [v]
*)

val step : ('env -> ('env, 'res) t) -> ('env, 'res) t
(**
  [step] is used to choose which strategy to apply given a current environment.
  If [f] is a function from ['env] to [('env, 'res) t] (that is, a function computing a
  strategy given an environment), then [step f] is the strategy which first apply [f] to 
  its input environment, and then apply the resulting strategy.
*)

val bind : ('env, 'res) t -> ('res -> ('env, 'res2) t) -> ('env, 'res2) t
(**
  [bind s f] first applies strategy [s]. If the result is a value [v],
  then the strategy [f v] is applied, otherwise the 
  status message of [s] is propagated.

  Note that if [s] returns an update notification together with an intermediate value [v],
  [f v] is then executed in the newly updated environment.
*)

val (let*) : ('env, 'res) t -> ('res -> ('env, 'res2) t) -> ('env, 'res2) t
(** Notation for [bind] *)

val fast_bind : ('env, 'res) t -> ('res -> ('env, 'res) t) -> ('env, 'res) t
(**
  [fast_bind s f] is exactly like [bind s f] but requires the result types of [s]
  and [f] to match. It is usually faster to use [fast_bind] that [fast] in this case.
*)

val (let+) : ('env, 'res) t -> ('res -> ('env, 'res) t) -> ('env, 'res) t
(** Notation for [fast_bind] *)

val (<|>) : ('env, 'res) t -> ('env, 'res) t -> ('env, 'res) t
(**
  [s1 <|> s2] is the strategy which first tries to apply strategy [s1]
  and then apply strategy [s2] is strategy [s1] fail or report a contradiction.
*)

val (<?>) : string -> ('env, 'res) t -> ('env, 'res) t
(**
  [msg <?> s] is a strategy printing the message [msg] to [stdout] and then applying
  strategy [s]
*)

val (<&>) : ('env, 'res) t -> ('env, 'res) t -> ('env, 'res) t
(**
  [s1 <&> s2] is a strategy which first applies strategy [s1] and then applies
  strategy [s2] if [s1] returns an update notification or a failure. In case 
  [s1] returned an update notification, [s2] is executed in
  the updated environment.
*)

val map : ('res -> 'res1) -> ('env, 'res) t -> ('env, 'res1) t
(** [map f s] is the strategy which first executes strategy [s] and then
    apply [f] to its result.
*)

val (=>) : ('env, 'res) t -> ('res -> 'res1) -> ('env, 'res1) t
(** Notation for [map] *)

val fast_map : ('res -> 'res) -> ('env, 'res) t -> ('env, 'res) t
(** Same as [map f s] but requires [f] to be of type ['a -> 'a].
    [map f s] is usually faster in this case.
*)

val (=>>) : ('env, 'res) t -> ('res -> 'res) -> ('env, 'res) t
(** Notation for [fast_map] *)

val ffix : (('env, 'res) t -> 'env -> ('env, 'res) t) -> ('env, 'res) t
(**
  [ffix] computes the fixpoint of a parametrized strategy.

  If [step] is a function computing a strategy given a strategy [recall] and a context [env],
  [fix step] computes a recursive strategy which is similar to [step] but where
  every call to the strategy [recall] are recursive calls to the strategy [step] itself.
  The recursion continues while [step] returns an update notification.
  It may not terminates !
*)

val stabilize : ('env, 'res) t -> ('env, 'res) t
(**
  [stabilize s] is a strategy which keeps applying [s]
  while it returns an update notification.
*)

val run : ('env, 'res) t -> 'env -> ('env, 'res) status
(**
  [run s e] executes strategy [s] in environnement [e]
*)

val run_opt : ('env, 'res) t -> 'env -> 'res option
(**
  [run_opt s e] is similar to [run s e] but convert the resulting [status]
  message to an optional value. If [s] returns only a value [v] in context [e], [run_opt s e] is [Some v]
  otherwise, [run_opt s e] is [None].
*)
