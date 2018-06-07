[%%import "config.h"]
open! Import
open  Std_internal
open! Int63.O

let module_name = "Core_kernel.Time_ns.Span"

type underlying = Int63.t

let arch_sixtyfour = Int.equal Sys.word_size 64
let round_nearest = Float.int63_round_nearest_exn

let float x = Int63.to_float x

(* [Span] is basically a [Int63].  It even silently ignores overflow. *)
module T = struct
  type t = Int63.t (* nanoseconds *)
  [@@deriving hash, bin_io, typerep]

  module Replace_polymorphic_compare = Int63.Replace_polymorphic_compare

  let zero    = Int63.zero
end

include T

open Replace_polymorphic_compare

module Parts = struct
  type t =
    { sign : Sign.t
    ; hr   : int
    ; min  : int
    ; sec  : int
    ; ms   : int
    ; us   : int
    ; ns   : int
    }
  [@@deriving compare, sexp]
end

let next t = Int63.succ t
let prev t = Int63.pred t

let nanosecond  = Int63.of_int 1
let microsecond = Int63.(of_int 1000 * nanosecond)
let millisecond = Int63.(of_int 1000 * microsecond)
let second      = Int63.(of_int 1000 * millisecond)
let minute      = Int63.(of_int 60 * second)
let hour        = Int63.(of_int 60 * minute)
let day         = Int63.(of_int 24 * hour)

(* Beyond [min_value..max_value], not every microsecond can be represented as a [float]
   number of seconds.  (In fact, it is around 135y, but we leave a small margin.)

   In the presence of silently ignored overflow, note that [t] is not actually bound to
   stay between these limits. *)
let max_value = Int63.(of_int 135 * of_int 365 * day)
let min_value = Int63.neg max_value

let create
      ?sign:(sign_  = Sign.Pos) (* rebind so not shadowed by [open Int63] below *)
      ?day:(days    = 0)
      ?(hr          = 0)
      ?min:(minutes = 0)
      ?(sec         = 0)
      ?(ms          = 0)
      ?(us          = 0)
      ?(ns          = 0)
      () =
  let open Int63 in
  let t =
    of_int days    * day
    + of_int hr      * hour
    + of_int minutes * minute
    + of_int sec     * second
    + of_int ms      * millisecond
    + of_int us      * microsecond
    + of_int ns      * nanosecond
  in
  match sign_ with Neg -> neg t | Pos | Zero -> t
;;

let to_parts t =
  let open Int63 in
  let mag = abs t in
  { Parts.
    sign = if t < zero then Neg else if t > zero then Pos else Zero
  ; hr = to_int_exn (mag / hour)
  ; min = to_int_exn ((rem mag hour) / minute)
  ; sec = to_int_exn ((rem mag minute) / second)
  ; ms = to_int_exn ((rem mag second) / millisecond)
  ; us = to_int_exn ((rem mag millisecond) / microsecond)
  ; ns = to_int_exn ((rem mag microsecond) / nanosecond)
  }
;;

let of_parts { Parts. sign; hr; min; sec; ms; us; ns } =
  create ~sign ~hr ~min ~sec ~ms ~us ~ns ()
;;

let of_ns       f = round_nearest f
let of_int63_ns i = i
let of_int_us   i = Int63.(of_int i * microsecond)
let of_int_ms   i = Int63.(of_int i * millisecond)
let of_int_sec  i = Int63.(of_int i * second)
let of_us       f = round_nearest (f *. float microsecond)
let of_ms       f = round_nearest (f *. float millisecond)
let of_sec      f = round_nearest (f *. float second)
let of_min      f = round_nearest (f *. float minute)
let of_hr       f = round_nearest (f *. float hour)
let of_day      f = round_nearest (f *. float day)

let of_sec_with_microsecond_precision sec =
  let us = round_nearest (sec *. 1e6) in
  of_int63_ns Int63.(us * of_int 1000)
;;

let of_int63_seconds x = x * second
let of_int32_seconds x = of_int63_seconds (Int63.of_int32 x)

let to_ns       t = float t
let to_int63_ns t =       t
let to_us       t = float t /. float microsecond
let to_ms       t = float t /. float millisecond
let to_sec      t = float t /. float second
let to_min      t = float t /. float minute
let to_hr       t = float t /. float hour
let to_day      t = float t /. float day
let to_int_us   t = Int63.(to_int_exn (t / microsecond))
let to_int_ms   t = Int63.(to_int_exn (t / millisecond))
let to_int_sec  t = Int63.(to_int_exn (t / second))

let to_int63_seconds_round_down_exn t = t /% second

let of_int_ns =
  if arch_sixtyfour
  then fun i -> of_int63_ns (Int63.of_int i)
  else fun _ -> failwith "Time_ns.Span.of_int_ns: unsupported on 32bit machines"

let to_int_ns =
  if arch_sixtyfour
  then fun t -> Int63.to_int_exn (to_int63_ns t)
  else fun _ -> failwith "Time_ns.Span.to_int_ns: unsupported on 32bit machines"

let (+)         t u = Int63.(+) t u
let (-)         t u = Int63.(-) t u
let abs             = Int63.abs
let neg             = Int63.neg
let scale       t f = round_nearest (float t *. f)
let scale_int63 t i = Int63.( * ) t i
let scale_int   t i = scale_int63 t (Int63.of_int i)
let div             = Int63.( /% )
let (/)         t f = round_nearest (float t /. f)
let (//)            = Int63.(//)

let to_proportional_float t = Int63.to_float t

let of_unit_of_time u =
  match (u : Unit_of_time.t) with
  | Nanosecond  -> nanosecond
  | Microsecond -> microsecond
  | Millisecond -> millisecond
  | Second      -> second
  | Minute      -> minute
  | Hour        -> hour
  | Day         -> day
;;

let to_unit_of_time t : Unit_of_time.t =
  let abs_t = abs t in
  if abs_t >= day         then Day         else
  if abs_t >= hour        then Hour        else
  if abs_t >= minute      then Minute      else
  if abs_t >= second      then Second      else
  if abs_t >= millisecond then Millisecond else
  if abs_t >= microsecond then Microsecond else
    Nanosecond
;;

module Stable = struct
  module V2 = struct
    module T = struct
      type nonrec t = t [@@deriving bin_io, compare, hash]

      let of_int63_exn t = of_int63_ns t
      let to_int63     t = to_int63_ns t

      module To_string = struct
        let number_of_digits_to_write ~span_part_magnitude =
          let open Int.O in
          if span_part_magnitude = 0 then 0
          else if span_part_magnitude <      10 then 1
          else if span_part_magnitude <     100 then 2
          else if span_part_magnitude <   1_000 then 3
          else if span_part_magnitude <  10_000 then 4
          else if span_part_magnitude < 100_000 then 5
          else assert false (* span part magnitudes are always < 100_000 *)

        let number_of_decimal_places_to_write ~billionths =
          let open Int.O in
          assert (billionths >= 0 && billionths <= 999_999_999);
          if billionths = 0 then 0
          else if billionths %          10 <> 0 then 9
          else if billionths %         100 <> 0 then 8
          else if billionths %       1_000 <> 0 then 7
          else if billionths %      10_000 <> 0 then 6
          else if billionths %     100_000 <> 0 then 5
          else if billionths %   1_000_000 <> 0 then 4
          else if billionths %  10_000_000 <> 0 then 3
          else if billionths % 100_000_000 <> 0 then 2
          else 1

        let write_char buf ~pos char =
          let open Int.O in
          Bytes.unsafe_set buf pos char;
          pos + 1

        let write_2_chars buf ~pos char1 char2 =
          let open Int.O in
          Bytes.unsafe_set buf  pos      char1;
          Bytes.unsafe_set buf (pos + 1) char2;
          pos + 2

        let write_digits buf ~pos ~digits int =
          let open Int.O in
          Digit_string_helpers.write_int63 buf ~pos ~digits (Int63.of_int int);
          pos + digits

        let write_decimals buf ~pos ~decimals ~billionths =
          let open Int.O in
          Digit_string_helpers.write_int63 buf ~pos ~digits:decimals
            (Int63.of_int (billionths / Int.pow 10 (9 - decimals)));
          pos + decimals

        let write_if_non_empty buf ~pos ~digits int suffix =
          let open Int.O in
          if digits = 0
          then pos
          else begin
            let pos = write_digits buf ~pos ~digits int in
            let pos = write_char   buf ~pos suffix      in
            pos
          end

        let nanos_of_millisecond =
          to_int63_ns millisecond
          |> Int63.to_int_exn

        let nanos_of_microsecond =
          to_int63_ns microsecond
          |> Int63.to_int_exn

        let int63_60 = Int63.of_int 60
        let int63_24 = Int63.of_int 24

        (* Units of seconds and smaller can be written in decimal notation without
           worrying about non-power-of-ten factors. *)
        module Decimal_unit = struct
          type t =
            | Second
            | Millisecond
            | Microsecond
            | Nanosecond
            | None
          [@@deriving compare, sexp_of]

          let create ~s ~ns =
            let open Int.O in
            if s  >  0                    then Second      else
            if ns >= nanos_of_millisecond then Millisecond else
            if ns >= nanos_of_microsecond then Microsecond else
            if ns >= 1                    then Nanosecond  else
              None

          let integer t ~s ~ns =
            let open Int.O in
            match t with
            | Second      -> s
            | Millisecond -> ns / nanos_of_millisecond
            | Microsecond -> ns / nanos_of_microsecond
            | Nanosecond  -> ns
            | None        -> 0

          let billionths t ~ns =
            let open Int.O in
            match t with
            | Second      ->  ns
            | Millisecond -> (ns % nanos_of_millisecond) *     1_000
            | Microsecond -> (ns % nanos_of_microsecond) * 1_000_000
            | Nanosecond  -> 0
            | None        -> 0

          let length t ~digits ~decimals =
            let open Int.O in
            let digits_len =
              match t with
              | Second                                 -> digits + 1
              | Millisecond | Microsecond | Nanosecond -> digits + 2
              | None                                   -> 0
            in
            let decimals_len = if decimals > 0 then decimals + 1 else 0 in
            digits_len + decimals_len

          let write_suffix t buf ~pos =
            match t with
            | Second      -> write_char    buf ~pos     's'
            | Millisecond -> write_2_chars buf ~pos 'm' 's'
            | Microsecond -> write_2_chars buf ~pos 'u' 's'
            | Nanosecond  -> write_2_chars buf ~pos 'n' 's'
            | None        -> pos

          let write t buf ~pos ~integer ~digits ~billionths ~decimals =
            let open Int.O in
            if digits = 0
            then pos
            else begin
              let pos = write_digits buf ~pos integer ~digits:digits in
              let pos =
                if decimals = 0
                then pos
                else begin
                  let pos = write_char buf ~pos '.' in
                  write_decimals buf ~pos ~billionths:billionths ~decimals:decimals
                end
              in
              write_suffix t buf ~pos
            end
        end

        let to_string t =
          if equal t zero
          then "0s"
          else begin
            let is_negative = ( < ) t zero in
            let seconds =
              Int63.( / )
                (to_int63_ns t)
                (to_int63_ns second)
            in
            let ns =
              Int63.rem
                (to_int63_ns t)
                (to_int63_ns second)
              |> Int63.to_int_exn
            in
            let seconds = Int63.abs seconds in
            let ns      = Int.abs   ns      in
            let s       = Int63.rem   seconds int63_60 |> Int63.to_int_exn in
            let minutes = Int63.( / ) seconds int63_60                     in
            let m       = Int63.rem   minutes int63_60 |> Int63.to_int_exn in
            let hours   = Int63.( / ) minutes int63_60                     in
            let h       = Int63.rem   hours   int63_24 |> Int63.to_int_exn in
            let d       = Int63.( / ) hours   int63_24 |> Int63.to_int_exn in
            let open Int.O in
            let digits_of_d = number_of_digits_to_write ~span_part_magnitude:d in
            let digits_of_h = number_of_digits_to_write ~span_part_magnitude:h in
            let digits_of_m = number_of_digits_to_write ~span_part_magnitude:m in
            let decimal_unit            = Decimal_unit.create                  ~s ~ns in
            let decimal_unit_integer    = Decimal_unit.integer    decimal_unit ~s ~ns in
            let decimal_unit_billionths = Decimal_unit.billionths decimal_unit    ~ns in
            let digits_of_decimal_unit =
              number_of_digits_to_write ~span_part_magnitude:decimal_unit_integer
            in
            let decimals_of_decimal_unit =
              number_of_decimal_places_to_write ~billionths:decimal_unit_billionths
            in
            let string_length =
              let sign_len = if is_negative then 1 else 0 in
              let d_len = if digits_of_d > 0 then digits_of_d + 1 else 0 in
              let h_len = if digits_of_h > 0 then digits_of_h + 1 else 0 in
              let m_len = if digits_of_m > 0 then digits_of_m + 1 else 0 in
              let decimal_unit_len =
                Decimal_unit.length decimal_unit
                  ~digits:   digits_of_decimal_unit
                  ~decimals: decimals_of_decimal_unit
              in
              sign_len + d_len + h_len + m_len + decimal_unit_len
            in
            assert (string_length > 0);
            let buf = Bytes.create string_length in
            let pos = 0 in
            let pos = if is_negative then write_char buf ~pos '-' else pos in
            let pos = write_if_non_empty buf ~pos ~digits:digits_of_d d 'd' in
            let pos = write_if_non_empty buf ~pos ~digits:digits_of_h h 'h' in
            let pos = write_if_non_empty buf ~pos ~digits:digits_of_m m 'm' in
            let pos =
              Decimal_unit.write decimal_unit buf ~pos
                ~integer:    decimal_unit_integer
                ~digits:     digits_of_decimal_unit
                ~billionths: decimal_unit_billionths
                ~decimals:   decimals_of_decimal_unit
            in
            assert (pos = string_length);
            Bytes.unsafe_to_string ~no_mutation_while_string_reachable:buf
          end
      end

      let to_string = To_string.to_string

      module Of_string = struct
        (* We do computations using negative numbers everywhere and test against
           things related to [Int63.min_value] rather than using positive numbers
           and testing against things related to [Int63.max_value] because the
           negative integer range is one wider than the positive integer range
           (-2**63 vs 2**63-1), and we need that to be able to handle Int63.min_value
           nicely. *)

        let int63_10 = Int63.of_int 10
        let min_mult10_without_underflow = Int63.(min_value / int63_10)

        let [@inline never] invalid_string string ~reason =
          raise_s [%message
            "Time_ns.Span.of_string: invalid string"
              (string : string)
              (reason : string)]

        (* Assumes x and y are both nonpositive *)
        let add_without_underflow ~string x y =
          let open Int63.O in
          let sum = x + y in
          if sum > x then begin
            invalid_string string ~reason:"span would be outside of int63 range"
          end;
          sum

        let add_neg_digit ~string int63 char =
          let open Int63.O in
          let digit = Int63.of_int (Char.get_digit_exn char) in
          if int63 < min_mult10_without_underflow then begin
            invalid_string string ~reason:"span would be outside of int63 range"
          end;
          add_without_underflow ~string (int63 * int63_10) (-digit)

        let min_factor_of span =
          Int63.( / ) Int63.min_value (to_int63_ns span)

        let min_days_without_underflow         = min_factor_of day
        let min_hours_without_underflow        = min_factor_of hour
        let min_minutes_without_underflow      = min_factor_of minute
        let min_seconds_without_underflow      = min_factor_of second
        let min_milliseconds_without_underflow = min_factor_of millisecond
        let min_microseconds_without_underflow = min_factor_of microsecond
        let min_nanoseconds_without_underflow  = min_factor_of nanosecond

        let min_without_underflow_of_unit_of_time unit_of_time =
          match (unit_of_time : Unit_of_time.t) with
          | Day         -> min_days_without_underflow
          | Hour        -> min_hours_without_underflow
          | Minute      -> min_minutes_without_underflow
          | Second      -> min_seconds_without_underflow
          | Millisecond -> min_milliseconds_without_underflow
          | Microsecond -> min_microseconds_without_underflow
          | Nanosecond  -> min_nanoseconds_without_underflow

        let negative_part
              string
              ~neg_integer
              ~decimal_pos
              ~end_pos
              ~unit_of_time
              ~round_ties_before_negating
          =
          let open Int.O in
          let scale =
            to_int63_ns (of_unit_of_time unit_of_time)
          in
          let min_without_underflow =
            min_without_underflow_of_unit_of_time unit_of_time
          in
          if Int63.( < ) neg_integer min_without_underflow then begin
            invalid_string string ~reason:"span would be outside of int63 range"
          end;
          let neg_integer_ns = Int63.( * ) neg_integer scale in
          let fraction_pos = decimal_pos + 1 in
          if fraction_pos >= end_pos
          then neg_integer_ns
          else begin
            let decimal_ns =
              Digit_string_helpers.read_int63_decimal string
                ~pos:fraction_pos
                ~scale
                ~decimals:(end_pos - fraction_pos)
                ~allow_underscore:true
                ~round_ties:round_ties_before_negating
            in
            add_without_underflow ~string neg_integer_ns (Int63.(~-) decimal_ns)
          end

        let of_string string =
          let open Int.O in
          let neg_ns = ref Int63.zero in
          let pos = ref 0 in
          let len = String.length string in
          if len = 0 then begin
            invalid_string string ~reason:"empty string"
          end;
          let is_negative =
            match String.unsafe_get string !pos with
            | '-' -> incr pos; true
            | '+' -> incr pos; false
            | _   -> false
          in
          let round_ties_before_negating : Digit_string_helpers.Round.t =
            (* Ultimately, we always round parsed spans towards positive infinity when
               the nearest round ns are equidistant. For example, "1.5ns" is read as
               2.0ns, and "-1.5ns" is read as -1ns. Since we read absolute values before
               applying the sign, we must choose our rounding direction based on the
               sign. Rounding decimal values happens before negating their magnitude. *)
            match is_negative with
            | false -> Toward_positive_infinity
            | true  -> Toward_negative_infinity
          in

          (* Loop over parts, like "5m" in "1h5m30s" *)
          while !pos < len do
            let has_digit = ref false in
            let neg_integer =
              let i             = ref Int63.zero in
              let end_of_digits = ref false      in
              while !pos < len && not !end_of_digits do
                let c = String.unsafe_get string !pos in
                match c with
                | '0' .. '9' ->
                  i := add_neg_digit ~string !i c;
                  has_digit := true;
                  incr pos
                | '_' -> incr pos
                | _   -> end_of_digits := true
              done;
              !i
            in

            let decimal_pos = !pos in
            begin
              if !pos < len && Char.equal '.' (String.unsafe_get string !pos)
              then begin
                incr pos;
                let end_of_decimals = ref false in
                while !pos < len && not !end_of_decimals do
                  match String.unsafe_get string !pos with
                  | '0' .. '9' -> has_digit := true; incr pos
                  | '_'        -> incr pos
                  | _          -> end_of_decimals := true
                done
              end
            end;
            let end_pos = !pos in
            if not !has_digit then begin
              invalid_string string ~reason:"no digits before unit suffix"
            end;

            let unit_of_time : Unit_of_time.t =
              if !pos + 1 < len && Char.equal 's' (String.unsafe_get string (!pos + 1))
              then begin
                match String.unsafe_get string !pos with
                | 'm' -> pos := !pos + 2; Millisecond
                | 'u' -> pos := !pos + 2; Microsecond
                | 'n' -> pos := !pos + 2; Nanosecond
                | _   -> invalid_string string ~reason:"unparseable unit suffix"
              end
              else if !pos < len
              then begin
                match String.unsafe_get string !pos with
                | 'd' -> incr pos; Day
                | 'h' -> incr pos; Hour
                | 'm' -> incr pos; Minute
                | 's' -> incr pos; Second
                | _   -> invalid_string string ~reason:"unparseable unit suffix"
              end
              else invalid_string string ~reason:"no unit suffix after digits"
            in

            let neg_nanos_of_part =
              negative_part string
                ~neg_integer
                ~decimal_pos
                ~end_pos
                ~unit_of_time
                ~round_ties_before_negating
            in
            neg_ns := add_without_underflow ~string !neg_ns neg_nanos_of_part;
          done;
          let ns =
            if is_negative
            then !neg_ns
            else begin
              if Int63.(=) !neg_ns Int63.min_value
              then invalid_string string ~reason:"span would be outside of int63 range"
              else Int63.(~-) !neg_ns
            end
          in
          of_int63_ns ns
        ;;
      end

      let of_string = Of_string.of_string

      let sexp_of_t t = Sexp.Atom (to_string t)

      let t_of_sexp sexp =
        match sexp with
        | Sexp.Atom x ->
          (try of_string x
           with exn -> of_sexp_error (Exn.to_string exn) sexp)
        | Sexp.List _ ->
          of_sexp_error "Time_ns.Span.Stable.V2.t_of_sexp: sexp must be an Atom" sexp
    end
    include T
    include Comparator.Stable.V1.Make (T)
  end
end

let to_string = Stable.V2.to_string
let of_string = Stable.V2.of_string
let sexp_of_t = Stable.V2.sexp_of_t
let t_of_sexp = Stable.V2.t_of_sexp

module Alternate_sexp = struct
  type nonrec t = t [@@deriving sexp]
end

include Comparable.Validate_with_zero(struct
    type nonrec t = t [@@deriving compare, sexp]
    let zero = zero
  end)

(* Functions required by [Robustly_comparable]: allows for [robust_comparison_tolerance]
   granularity.

   A microsecond is a reasonable granularity because there is very little network
   activity that can be measured to sub-microsecond resolution. *)
let robust_comparison_tolerance = microsecond
let (>=.) t u = t >= Int63.(u - robust_comparison_tolerance)
let (<=.) t u = t <= Int63.(u + robust_comparison_tolerance)
let (=.) t u = Int63.(abs (t - u)) <= robust_comparison_tolerance
let (>.) t u = t > Int63.(u + robust_comparison_tolerance)
let (<.) t u = t < Int63.(u - robust_comparison_tolerance)
let (<>.) t u = Int63.(abs (t - u)) > robust_comparison_tolerance
let robustly_compare t u = if t <. u then -1 else if t >. u then 1 else 0

(* We don't just convert to [Time.Span.t] and use the conversion there because our
   [to_span] conversion is limited to microsecond precision. *)
let to_string_hum ?(delimiter='_') ?(decimals=3) ?(align_decimal=false) ?unit_of_time t
  =
  let float, suffix =
    match Option.value unit_of_time ~default:(to_unit_of_time t) with
    | Day         -> to_day t, "d"
    | Hour        -> to_hr  t, "h"
    | Minute      -> to_min t, "m"
    | Second      -> to_sec t, "s"
    | Millisecond -> to_ms  t, "ms"
    | Microsecond -> to_us  t, "us"
    | Nanosecond  -> to_ns  t, "ns"
  in
  let prefix =
    Float.to_string_hum float ~delimiter ~decimals ~strip_zero:(not align_decimal)
  in
  let suffix =
    if align_decimal && Int.(=) (String.length suffix) 1
    then suffix ^ " "
    else suffix
  in
  prefix ^ suffix
;;

[%%ifdef JSC_ARCH_SIXTYFOUR]
external since_unix_epoch_or_zero : unit -> t
  = "core_kernel_time_ns_gettime_or_zero" [@@noalloc]
[%%else]
external since_unix_epoch_or_zero : unit -> t
  = "core_kernel_time_ns_gettime_or_zero"
[%%endif]

[%%ifdef JSC_POSIX_TIMERS]
let [@inline never] gettime_failed () = failwith "clock_gettime(CLOCK_REALTIME) failed"
[%%else]
let [@inline never] gettime_failed () = failwith "gettimeofday failed"
[%%endif]

let since_unix_epoch () =
  let t = since_unix_epoch_or_zero () in
  if t <> zero then t else gettime_failed ()
;;

let random ?state () =
  Int63.random ?state (max_value     + Int63.one) -
  Int63.random ?state (neg min_value + Int63.one)
;;

let randomize t ~percent =
  Span_helpers.randomize t ~percent ~scale

let to_short_string t =
  let { sign; hr; min; sec; ms; us; ns } : Parts.t = to_parts t in
  Span_helpers.short_string ~sign ~hr ~min ~sec ~ms ~us ~ns

include Pretty_printer.Register (struct
    type nonrec t = t
    let to_string = to_string
    let module_name = module_name
  end)

include Hashable.Make_binable (struct
    type nonrec t = t [@@deriving bin_io, compare, hash, sexp]
  end)

module C = Comparable.Make_binable (struct
    type nonrec t = t [@@deriving bin_io, compare, sexp]
  end)

include (C : module type of C
         with module Replace_polymorphic_compare := Replace_polymorphic_compare)

(* re-include comparisons to shadow the un-inlineable ones from [Comparable] *)
include Replace_polymorphic_compare

module Private = struct
  module Parts = Parts
  let of_parts = of_parts
  let to_parts = to_parts
end
