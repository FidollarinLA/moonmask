///|
let max_abs : Int64 = 999999999999999L

///|
let max_abs_f : Double = 999999999999999.0

///|
priv struct End {
  value : Double
  inclusive : Bool
}

///|
priv struct Dec {
  ip : Int64
  numer : Int64
  scale : Int
  inclusive : Bool
}

///|
fn pow10_i64(n : Int) -> Int64 {
  let mut p = 1L
  for _ in 0..<n {
    p = p * 10L
  }
  p
}

///|
fn read_number_field(
  fields : Map[String, Json],
  key : String,
) -> Double? raise SchemaError {
  match fields.get(key) {
    None => None
    Some(Number(n, ..)) => Some(n)
    Some(_) => raise Invalid(key)
  }
}

///|
fn read_exclusive(
  fields : Map[String, Json],
  key : String,
) -> Double? raise SchemaError {
  match fields.get(key) {
    None => None
    Some(True | False) => raise Unsupported(key)
    Some(Number(n, ..)) => Some(n)
    Some(_) => raise Invalid(key)
  }
}

///|
fn read_lower(fields : Map[String, Json]) -> End? raise SchemaError {
  let incl = read_number_field(fields, "minimum")
  let excl = read_exclusive(fields, "exclusiveMinimum")
  match (incl, excl) {
    (None, None) => None
    (Some(m), None) => Some({ value: m, inclusive: true, })
    (None, Some(e)) => Some({ value: e, inclusive: false, })
    (Some(m), Some(e)) =>
      if m > e {
        Some({ value: m, inclusive: true, })
      } else {
        Some({ value: e, inclusive: false, })
      }
  }
}

///|
fn read_upper(fields : Map[String, Json]) -> End? raise SchemaError {
  let incl = read_number_field(fields, "maximum")
  let excl = read_exclusive(fields, "exclusiveMaximum")
  match (incl, excl) {
    (None, None) => None
    (Some(m), None) => Some({ value: m, inclusive: true, })
    (None, Some(e)) => Some({ value: e, inclusive: false, })
    (Some(m), Some(e)) =>
      if m < e {
        Some({ value: m, inclusive: true, })
      } else {
        Some({ value: e, inclusive: false, })
      }
  }
}

///|
fn read_ends(fields : Map[String, Json]) -> (End?, End?) raise SchemaError {
  (read_lower(fields), read_upper(fields))
}

///|
fn range_ok(low : End?, high : End?) -> Bool {
  match (low, high) {
    (None, _) | (_, None) => true
    (Some(l), Some(h)) =>
      l.value < h.value || (l.value == h.value && l.inclusive && h.inclusive)
  }
}

///|
fn ensure_i64(n : Double) -> Int64 raise SchemaError {
  if n != n || n > max_abs_f || n < -max_abs_f {
    raise Unsupported("numeric bound")
  }
  n.to_int64()
}

///|
fn lower_int(low : End?) -> Int64 raise SchemaError {
  match low {
    None => -max_abs
    Some({ value, inclusive, }) =>
      if inclusive {
        ensure_i64(value.ceil())
      } else {
        ensure_i64(value.floor()) + 1L
      }
  }
}

///|
fn upper_int(high : End?) -> Int64 raise SchemaError {
  match high {
    None => max_abs
    Some({ value, inclusive, }) =>
      if inclusive {
        ensure_i64(value.floor())
      } else {
        ensure_i64(value.ceil()) - 1L
      }
  }
}

///|
fn digit_list(text : String) -> Array[Int] {
  let out = []
  for c in text {
    out.push(c.to_int() - '0'.to_int())
  }
  out
}

///|
fn digits_from(xs : Array[Int], start : Int) -> Array[Int] {
  let out = []
  let mut i = start
  while i < xs.length() {
    out.push(xs[i])
    i += 1
  }
  out
}

///|
fn digits_to_string(xs : Array[Int]) -> String {
  let buf = StringBuilder()
  for d in xs {
    buf.write_char((48 + d).unsafe_to_char())
  }
  buf.to_string()
}

///|
fn repeat_digit(d : Int, n : Int) -> Array[Int] {
  let out = []
  for _ in 0..<n {
    out.push(d)
  }
  out
}

///|
fn digit_s(d : Int) -> String {
  (48 + d).unsafe_to_char().to_string()
}

///|
fn digits_prefix(xs : Array[Int], end : Int) -> String {
  let buf = StringBuilder()
  for i in 0..<end {
    buf.write_char((48 + xs[i]).unsafe_to_char())
  }
  buf.to_string()
}

///|
fn all_digits(xs : Array[Int], d : Int) -> Bool {
  for x in xs {
    if x != d {
      return false
    }
  }
  true
}

///|
fn same_len_digits(a : Array[Int], b : Array[Int]) -> String raise SchemaError {
  if a.length() > 0 && all_digits(a, 0) && all_digits(b, 9) {
    if a.length() <= 1 {
      return "[0-9]"
    }
    return "[0-9]{\{a.length()}}"
  }
  let mut i = 0
  while i < a.length() && a[i] == b[i] {
    i += 1
  }
  if i == a.length() {
    return digits_to_string(a)
  }
  if a[i] > b[i] {
    raise Invalid("numeric range")
  }
  let prefix = digits_prefix(a, i)
  let rest = a.length() - i - 1
  let parts = []
  let left_tail = if rest == 0 {
    ""
  } else {
    same_len_digits(digits_from(a, i + 1), repeat_digit(9, rest))
  }
  parts.push(prefix + digit_s(a[i]) + left_tail)
  if b[i] > a[i] + 1 {
    let lo = (48 + a[i] + 1).unsafe_to_char()
    let hi = (48 + b[i] - 1).unsafe_to_char()
    let mid = if lo == hi { lo.to_string() } else { "[\{lo}-\{hi}]" }
    let tail = if rest == 0 {
      ""
    } else if rest == 1 {
      "[0-9]"
    } else {
      "[0-9]{\{rest}}"
    }
    parts.push(prefix + mid + tail)
  }
  let right_tail = if rest == 0 {
    ""
  } else {
    same_len_digits(repeat_digit(0, rest), digits_from(b, i + 1))
  }
  parts.push(prefix + digit_s(b[i]) + right_tail)
  alt(parts)
}

///|
fn same_len(a : String, b : String) -> String raise SchemaError {
  same_len_digits(digit_list(a), digit_list(b))
}

///|
fn digits_of(n : Int64) -> String {
  if n == 0L {
    "0"
  } else {
    n.to_string()
  }
}

///|
fn pos_regex(lo : Int64, hi : Int64) -> String raise SchemaError {
  if lo == 0L {
    if hi == 0L {
      return "0"
    }
    return alt(["0", pos_regex(1L, hi)])
  }
  let a = digits_of(lo)
  let b = digits_of(hi)
  if a.length() == b.length() {
    return same_len(a, b)
  }
  let parts = []
  parts.push(same_len(a, digits_of(pow10_i64(a.length()) - 1L)))
  let mut len = a.length() + 1
  while len < b.length() {
    if len == 1 {
      parts.push("[1-9]")
    } else {
      parts.push("[1-9][0-9]{\{len - 1}}")
    }
    len += 1
  }
  parts.push(same_len(digits_of(pow10_i64(b.length() - 1)), b))
  alt(parts)
}

///|
fn integer_span_regex(lo : Int64, hi : Int64) -> String raise SchemaError {
  let parts = []
  if lo < 0L {
    let mag_hi = -lo
    let mag_lo = if hi < 0L { -hi } else { 1L }
    parts.push("-" + pos_regex(mag_lo, mag_hi))
  }
  if lo <= 0L && hi >= 0L {
    parts.push("0")
  }
  if hi > 0L {
    let pos_lo = if lo > 0L { lo } else { 1L }
    parts.push(pos_regex(pos_lo, hi))
  }
  alt(parts)
}

///|
fn integer_bounds_regex(low : End?, high : End?) -> String raise SchemaError {
  if !range_ok(low, high) {
    raise Invalid("numeric range")
  }
  let lo = lower_int(low)
  let hi = upper_int(high)
  if lo > hi {
    raise Invalid("numeric range")
  }
  integer_span_regex(lo, hi)
}

///|
fn copy_range(text : String, start : Int, end : Int) -> String {
  let buf = StringBuilder()
  let mut i = 0
  for c in text {
    if i >= start && i < end {
      buf.write_char(c)
    }
    i += 1
  }
  buf.to_string()
}

///|
fn parse_exp(text : String) -> Int raise SchemaError {
  let mut sign = 1
  let mut n = 0
  let mut started = false
  for c in text {
    if !started && c == '+' {
      started = true
      continue
    }
    if !started && c == '-' {
      sign = -1
      started = true
      continue
    }
    if c < '0' || c > '9' {
      raise Unsupported("numeric bound")
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
    started = true
  }
  if !started {
    raise Unsupported("numeric bound")
  }
  n * sign
}

///|
fn decode_abs(n : Double, inclusive : Bool) -> Dec raise SchemaError {
  if n != n || n < 0.0 || n > max_abs_f {
    raise Unsupported("numeric bound")
  }
  let text = n.to_string()
  let mut exp_at = -1
  let mut i = 0
  for c in text {
    if c == 'e' || c == 'E' {
      exp_at = i
      break
    }
    i += 1
  }
  let body = if exp_at < 0 { text } else { copy_range(text, 0, exp_at) }
  let exp = if exp_at < 0 {
    0
  } else {
    parse_exp(copy_range(text, exp_at + 1, text.length()))
  }
  let digits = []
  let mut dot = -1
  let mut pos = 0
  for c in body {
    if c == '.' && dot < 0 {
      dot = pos
    } else if c >= '0' && c <= '9' {
      digits.push(c.to_int() - '0'.to_int())
    } else {
      raise Unsupported("numeric bound")
    }
    pos += 1
  }
  if digits.is_empty() {
    raise Unsupported("numeric bound")
  }
  let frac_len = if dot < 0 { 0 } else { body.length() - dot - 1 }
  let mut scale = frac_len - exp
  if scale < 0 {
    for _ in 0..<-scale {
      digits.push(0)
    }
    scale = 0
  }
  if scale > 15 || digits.length() - scale > 15 {
    raise Unsupported("numeric bound")
  }
  let mut all = 0L
  for d in digits {
    all = all * 10L + Int64::from_int(d)
  }
  let ip = if scale == 0 { all } else { all / pow10_i64(scale) }
  let mut numer = if scale == 0 { 0L } else { all % pow10_i64(scale) }
  let mut sc = scale
  while sc > 0 && numer % 10L == 0L {
    numer = numer / 10L
    sc = sc - 1
  }
  { ip, numer, scale: sc, inclusive, }
}

///|
fn cmp_frac(n1 : Int64, s1 : Int, n2 : Int64, s2 : Int) -> Int {
  let scale = if s1 > s2 { s1 } else { s2 }
  let left = n1 * pow10_i64(scale - s1)
  let right = n2 * pow10_i64(scale - s2)
  if left < right {
    -1
  } else if left > right {
    1
  } else {
    0
  }
}

///|
fn cmp_abs(a : Dec, b : Dec) -> Int {
  if a.ip < b.ip {
    -1
  } else if a.ip > b.ip {
    1
  } else {
    cmp_frac(a.numer, a.scale, b.numer, b.scale)
  }
}

///|
fn interval_empty(low : Dec, high : Dec) -> Bool {
  let order = cmp_abs(low, high)
  order > 0 || (order == 0 && !(low.inclusive && high.inclusive))
}

///|
fn pad_i64(n : Int64, width : Int) -> String {
  let s = n.to_string()
  let buf = StringBuilder()
  for _ in s.length()..<width {
    buf.write_char('0')
  }
  buf.write_string(s)
  buf.to_string()
}

///|
fn lower_digits(numer : Int64, scale : Int, k : Int, inclusive : Bool) -> Int64 {
  if k >= scale {
    let exact = numer * pow10_i64(k - scale)
    if inclusive {
      exact
    } else {
      exact + 1L
    }
  } else {
    let den = pow10_i64(scale - k)
    if inclusive {
      if numer % den == 0L {
        numer / den
      } else {
        numer / den + 1L
      }
    } else {
      numer / den + 1L
    }
  }
}

///|
fn upper_digits(numer : Int64, scale : Int, k : Int, inclusive : Bool) -> Int64 {
  if k >= scale {
    let exact = numer * pow10_i64(k - scale)
    if inclusive {
      exact
    } else {
      exact - 1L
    }
  } else {
    let den = pow10_i64(scale - k)
    if inclusive {
      numer / den
    } else {
      let ceil = if numer % den == 0L { numer / den } else { numer / den + 1L }
      ceil - 1L
    }
  }
}

///|
fn frac_between(low : Dec?, high : Dec?) -> String? raise SchemaError {
  let parts = []
  for k in 1..<16 {
    let cap = pow10_i64(k) - 1L
    let mut lo = 0L
    let mut hi = cap
    match low {
      None => ()
      Some(bound) => {
        let t = lower_digits(bound.numer, bound.scale, k, bound.inclusive)
        if t > lo {
          lo = t
        }
      }
    }
    match high {
      None => ()
      Some(bound) => {
        let t = upper_digits(bound.numer, bound.scale, k, bound.inclusive)
        if t < hi {
          hi = t
        }
      }
    }
    if lo < 0L {
      lo = 0L
    }
    if hi > cap {
      hi = cap
    }
    if lo <= hi {
      parts.push(same_len(pad_i64(lo, k), pad_i64(hi, k)))
    }
  }
  if parts.is_empty() {
    None
  } else {
    Some(alt(parts))
  }
}

///|
fn in_full(ip : Int64, flo : Int64, fhi : Int64) -> Bool {
  flo <= fhi && ip >= flo && ip <= fhi
}

///|
fn assemble_fractions(low : Dec, high : Dec) -> String? raise SchemaError {
  if interval_empty(low, high) {
    return None
  }
  let flo = if low.numer == 0L && low.inclusive { low.ip } else { low.ip + 1L }
  let fhi = high.ip - 1L
  let parts = []
  if flo <= fhi {
    parts.push(pos_regex(flo, fhi) + "\\.[0-9]{1,15}")
  }
  if low.ip <= high.ip && !in_full(low.ip, flo, fhi) {
    let upper = if low.ip == high.ip { Some(high) } else { None }
    match frac_between(Some(low), upper) {
      None => ()
      Some(fr) => parts.push(pos_regex(low.ip, low.ip) + "\\." + fr)
    }
  }
  if high.ip != low.ip && !in_full(high.ip, flo, fhi) {
    match frac_between(None, Some(high)) {
      None => ()
      Some(fr) => parts.push(pos_regex(high.ip, high.ip) + "\\." + fr)
    }
  }
  if parts.is_empty() {
    None
  } else {
    Some(alt(parts))
  }
}

///|
fn positive_fractions(low : End?, high : End?) -> String? raise SchemaError {
  match high {
    Some({ value, .. }) if value < 0.0 => return None
    Some({ value: 0.0, .. }) => return None
    _ => ()
  }
  let mag_low = match low {
    None => { ip: 0L, numer: 0L, scale: 0, inclusive: false, }
    Some({ value, .. }) if value < 0.0 =>
      { ip: 0L, numer: 0L, scale: 0, inclusive: false, }
    Some({ value: 0.0, inclusive, }) =>
      { ip: 0L, numer: 0L, scale: 0, inclusive, }
    Some({ value, inclusive, }) => decode_abs(value, inclusive)
  }
  let mag_high = match high {
    None => { ip: max_abs, numer: 0L, scale: 0, inclusive: true, }
    Some({ value, inclusive, }) => decode_abs(value, inclusive)
  }
  assemble_fractions(mag_low, mag_high)
}

///|
fn negative_fractions(low : End?, high : End?) -> String? raise SchemaError {
  match low {
    Some({ value, .. }) if value > 0.0 => return None
    Some({ value: 0.0, .. }) => return None
    _ => ()
  }
  let mag_low = match high {
    None => { ip: 0L, numer: 0L, scale: 0, inclusive: false, }
    Some({ value, .. }) if value > 0.0 =>
      { ip: 0L, numer: 0L, scale: 0, inclusive: false, }
    Some({ value, inclusive, }) => decode_abs(-value, inclusive)
  }
  let mag_high = match low {
    None => { ip: max_abs, numer: 0L, scale: 0, inclusive: true, }
    Some({ value, inclusive, }) => decode_abs(-value, inclusive)
  }
  match assemble_fractions(mag_low, mag_high) {
    None => None
    Some(body) => Some("-" + body)
  }
}

///|
fn bounded_number(low : End?, high : End?) -> String raise SchemaError {
  if !range_ok(low, high) {
    raise Invalid("numeric range")
  }
  let parts = []
  let lo = lower_int(low)
  let hi = upper_int(high)
  if lo <= hi {
    parts.push(integer_span_regex(lo, hi))
    if lo <= 0L && hi >= 0L {
      parts.push("0\\.0{1,15}")
    }
  }
  match positive_fractions(low, high) {
    None => ()
    Some(body) => parts.push(body)
  }
  match negative_fractions(low, high) {
    None => ()
    Some(body) => parts.push(body)
  }
  if parts.is_empty() {
    raise Invalid("numeric range")
  }
  alt(parts)
}
