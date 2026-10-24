#if os(iOS) || os(macOS)
import JavaScriptCore

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

enum ModuleScriptWebGlobals {
     
     
     
     
     
     
     
    @discardableResult
    static func install(into context: JSContext) -> Bool {
        let handler = context.exceptionHandler
        var threw = false
        context.exceptionHandler = { _, _ in threw = true }
        context.evaluateScript(source)
        context.exceptionHandler = handler
        return !threw
    }

     
     
    private static let source = ##"""
(function (global) {
'use strict';

var CHUNK = 8192;

function define(name, value, enumerable) {
  Object.defineProperty(global, name, { value: value, writable: true, enumerable: enumerable, configurable: true });
}

// Web IDL members are enumerable, and an instance says its interface's name.
function expose(constructor, tag) {
  var prototype = constructor.prototype;
  Object.getOwnPropertyNames(prototype).forEach(function (key) {
    if (key === 'constructor') return;
    var descriptor = Object.getOwnPropertyDescriptor(prototype, key);
    descriptor.enumerable = true;
    Object.defineProperty(prototype, key, descriptor);
  });
  Object.defineProperty(prototype, Symbol.toStringTag, { value: tag, configurable: true });
}

function required(args, count, name) {
  if (args.length < count) {
    throw new TypeError(name + ': ' + count + ' argument' + (count > 1 ? 's' : '') + ' required, but only ' + args.length + ' present.');
  }
}

function toDOMString(value) {
  if (typeof value === 'symbol') throw new TypeError('Cannot convert a Symbol value to a string');
  return String(value);
}

// Web IDL's USVString: a lone surrogate becomes U+FFFD.
function toUSV(value) {
  var s = toDOMString(value);
  return /[\uD800-\uDFFF]/.test(s) ? wellFormed(s) : s;
}

function wellFormed(s) {
  var out = '', start = 0;
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i);
    if (c < 0xD800 || c > 0xDFFF) continue;
    if (c <= 0xDBFF && i + 1 < s.length) {
      var d = s.charCodeAt(i + 1);
      if (d >= 0xDC00 && d <= 0xDFFF) { i++; continue; }
    }
    out += s.slice(start, i) + '\uFFFD';
    start = i + 1;
  }
  return out + s.slice(start);
}

function isObject(value) {
  return value !== null && (typeof value === 'object' || typeof value === 'function');
}

// ---- UTF-8 --------------------------------------------------------------

function utf8Length(s) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i);
    if (c < 0x80) n += 1;
    else if (c < 0x800) n += 2;
    else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length && (s.charCodeAt(i + 1) & 0xFC00) === 0xDC00) { n += 4; i++; }
    else n += 3;
  }
  return n;
}

// Writes the UTF-8 of as many whole code points of `s` as fit in `bytes`, a
// lone surrogate as U+FFFD; returns [code units read, bytes written].
function utf8Write(s, bytes) {
  var capacity = bytes.length, length = s.length, w = 0, i = 0;
  for (; i < length; i++) {
    var c = s.charCodeAt(i);
    if (c < 0x80) {
      if (w >= capacity) break;
      bytes[w++] = c;
      continue;
    }
    if (c < 0x800) {
      if (w + 2 > capacity) break;
      bytes[w++] = 0xC0 | (c >> 6);
      bytes[w++] = 0x80 | (c & 0x3F);
      continue;
    }
    if (c >= 0xD800 && c <= 0xDFFF) {
      var d = c <= 0xDBFF && i + 1 < length ? s.charCodeAt(i + 1) : 0;
      if (d >= 0xDC00 && d <= 0xDFFF) {
        if (w + 4 > capacity) break;
        var cp = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
        bytes[w++] = 0xF0 | (cp >> 18);
        bytes[w++] = 0x80 | ((cp >> 12) & 0x3F);
        bytes[w++] = 0x80 | ((cp >> 6) & 0x3F);
        bytes[w++] = 0x80 | (cp & 0x3F);
        i++;
        continue;
      }
      c = 0xFFFD;
    }
    if (w + 3 > capacity) break;
    bytes[w++] = 0xE0 | (c >> 12);
    bytes[w++] = 0x80 | ((c >> 6) & 0x3F);
    bytes[w++] = 0x80 | (c & 0x3F);
  }
  return [i, w];
}

function utf8Bytes(s) {
  var bytes = new Uint8Array(utf8Length(s));
  utf8Write(s, bytes);
  return bytes;
}

function newDecoderState(fatal, ignoreBOM) {
  return { fatal: fatal, ignoreBOM: ignoreBOM, doNotFlush: false, bomSeen: false, needed: 0, seen: 0, cp: 0, lower: 0x80, upper: 0xBF };
}

function resetDecoder(d) {
  d.doNotFlush = false; d.bomSeen = false; d.needed = 0; d.seen = 0; d.cp = 0; d.lower = 0x80; d.upper = 0xBF;
}

function decodeError(d) {
  resetDecoder(d);
  return new TypeError('The encoded data was not valid for encoding utf-8');
}

// The Encoding Standard's UTF-8 decoder over `bytes`, from and back into the
// state `d`; at the end of the stream (not `stream`) a sequence still open is
// an error.
function utf8Decode(d, bytes, stream) {
  var needed = d.needed, seen = d.seen, cp = d.cp, lower = d.lower, upper = d.upper;
  var fatal = d.fatal, bomPending = !d.ignoreBOM && !d.bomSeen;
  var length = bytes.length;
  // Nothing held over and every byte ASCII: the bytes are the code units, and
  // the first of them is the stream's start (no BOM is left to come).
  if (needed === 0 && isASCII(bytes)) {
    if (bomPending && length > 0) d.bomSeen = true;
    var ascii = '';
    for (var start = 0; start < length; start += CHUNK) {
      ascii += String.fromCharCode.apply(null, bytes.subarray(start, Math.min(length, start + CHUNK)));
    }
    return ascii;
  }
  var units = new Uint16Array(Math.min(length, CHUNK) + 2), n = 0, text = '';
  for (var i = 0; i <= length; i++) {
    var out;
    if (i === length) {
      if (stream || needed === 0) break;
      needed = seen = cp = 0; lower = 0x80; upper = 0xBF;
      out = -2;
    } else {
      var b = bytes[i];
      out = -1;
      if (needed === 0) {
        if (b < 0x80) out = b;
        else if (b >= 0xC2 && b <= 0xDF) { needed = 1; cp = b & 0x1F; }
        else if (b >= 0xE0 && b <= 0xEF) {
          if (b === 0xE0) lower = 0xA0; else if (b === 0xED) upper = 0x9F;
          needed = 2; cp = b & 0x0F;
        } else if (b >= 0xF0 && b <= 0xF4) {
          if (b === 0xF0) lower = 0x90; else if (b === 0xF4) upper = 0x8F;
          needed = 3; cp = b & 0x07;
        } else out = -2;
      } else if (b < lower || b > upper) {
        needed = seen = cp = 0; lower = 0x80; upper = 0xBF;
        i--;
        out = -2;
      } else {
        lower = 0x80; upper = 0xBF;
        cp = (cp << 6) | (b & 0x3F);
        if (++seen === needed) { out = cp; needed = seen = cp = 0; }
      }
      if (out === -1) continue;
    }
    if (out === -2) {
      if (fatal) throw decodeError(d);
      out = 0xFFFD;
    }
    if (bomPending) {
      bomPending = false;
      d.bomSeen = true;
      if (out === 0xFEFF) continue;
    }
    if (out < 0x10000) {
      units[n++] = out;
    } else {
      out -= 0x10000;
      units[n++] = 0xD800 + (out >> 10);
      units[n++] = 0xDC00 + (out & 0x3FF);
    }
    if (n >= CHUNK) {
      text += String.fromCharCode.apply(null, units.subarray(0, n));
      n = 0;
    }
  }
  d.needed = needed; d.seen = seen; d.cp = cp; d.lower = lower; d.upper = upper;
  return n ? text + String.fromCharCode.apply(null, units.subarray(0, n)) : text;
}

function isASCII(bytes) {
  for (var i = 0; i < bytes.length; i++) if (bytes[i] >= 0x80) return false;
  return true;
}

// UTF-8 decode without BOM: what URL parsing does with percent-decoded bytes.
function utf8DecodeReplacing(bytes) {
  return utf8Decode(newDecoderState(false, true), bytes, false);
}

// ---- TextEncoder, TextDecoder -------------------------------------------

var typedArrayTag = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype), Symbol.toStringTag).get;
var arrayBufferLength = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;

function bytesOf(input) {
  if (ArrayBuffer.isView(input)) return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
  try {
    arrayBufferLength.call(input);
  } catch (e) {
    if (typeof SharedArrayBuffer !== 'function' || !(input instanceof SharedArrayBuffer)) {
      throw new TypeError("The provided value is not of type '(ArrayBuffer or ArrayBufferView)'");
    }
  }
  return new Uint8Array(input);
}

var encoders = new WeakMap();
var decoders = new WeakMap();

function decoderOf(self) {
  var d = decoders.get(self);
  if (d === undefined) throw new TypeError('Illegal invocation');
  return d;
}

function dictionary(value, name) {
  if (value === undefined || value === null) return {};
  if (!isObject(value)) throw new TypeError(name + ': the options are not an object');
  return value;
}

var Encoder = class TextEncoder {
  constructor() {
    encoders.set(this, true);
  }
  get encoding() {
    if (!encoders.has(this)) throw new TypeError('Illegal invocation');
    return 'utf-8';
  }
  encode(input = '') {
    if (!encoders.has(this)) throw new TypeError('Illegal invocation');
    return utf8Bytes(toDOMString(input));
  }
  encodeInto(source, destination) {
    if (!encoders.has(this)) throw new TypeError('Illegal invocation');
    required(arguments, 2, 'encodeInto');
    var s = toDOMString(source);
    if (typedArrayTag.call(destination) !== 'Uint8Array') {
      throw new TypeError("encodeInto: the destination is not of type 'Uint8Array'");
    }
    var result = utf8Write(s, destination);
    return { read: result[0], written: result[1] };
  }
};
expose(Encoder, 'TextEncoder');

var UTF8_LABELS = ['unicode-1-1-utf-8', 'unicode11utf8', 'unicode20utf8', 'utf-8', 'utf8', 'x-unicode20utf8'];

var Decoder = class TextDecoder {
  constructor(label = 'utf-8', options = undefined) {
    var text = toDOMString(label);
    var options_ = dictionary(options, 'TextDecoder');
    if (UTF8_LABELS.indexOf(text.replace(/^[\t\n\f\r ]+|[\t\n\f\r ]+$/g, '').toLowerCase()) < 0) {
      throw new RangeError("The encoding label provided ('" + text + "') is invalid.");
    }
    decoders.set(this, newDecoderState(!!options_.fatal, !!options_.ignoreBOM));
  }
  get encoding() { decoderOf(this); return 'utf-8'; }
  get fatal() { return decoderOf(this).fatal; }
  get ignoreBOM() { return decoderOf(this).ignoreBOM; }
  decode(input = undefined, options = undefined) {
    var d = decoderOf(this);
    var bytes = input === undefined ? new Uint8Array(0) : bytesOf(input);
    var stream = !!dictionary(options, 'decode').stream;
    if (!d.doNotFlush) resetDecoder(d);
    d.doNotFlush = stream;
    return utf8Decode(d, bytes, stream);
  }
};
expose(Decoder, 'TextDecoder');

// ---- atob, btoa ---------------------------------------------------------

var BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function invalidCharacter(message) {
  var error = new Error(message);
  Object.defineProperty(error, 'name', { value: 'InvalidCharacterError', writable: true, configurable: true });
  Object.defineProperty(error, 'code', { value: 5, writable: true, configurable: true });
  return error;
}

// Named expressions: a declaration would hide the global this checks for.
var btoa_ = function btoa(data) {
  required(arguments, 1, 'btoa');
  var s = toDOMString(data);
  if (/[^\u0000-\u00FF]/.test(s)) {
    throw invalidCharacter('The string to be encoded contains characters outside of the Latin1 range.');
  }
  var length = s.length, units = new Uint16Array(Math.min(Math.ceil(length / 3) * 4, CHUNK) + 4), n = 0, text = '';
  var i = 0;
  for (; i + 2 < length; i += 3) {
    var t = (s.charCodeAt(i) << 16) | (s.charCodeAt(i + 1) << 8) | s.charCodeAt(i + 2);
    units[n++] = BASE64.charCodeAt(t >> 18);
    units[n++] = BASE64.charCodeAt((t >> 12) & 63);
    units[n++] = BASE64.charCodeAt((t >> 6) & 63);
    units[n++] = BASE64.charCodeAt(t & 63);
    if (n >= CHUNK) {
      text += String.fromCharCode.apply(null, units.subarray(0, n));
      n = 0;
    }
  }
  if (i < length) {
    var a = s.charCodeAt(i), b = i + 1 < length ? s.charCodeAt(i + 1) : 0;
    units[n++] = BASE64.charCodeAt(a >> 2);
    units[n++] = BASE64.charCodeAt(((a & 3) << 4) | (b >> 4));
    units[n++] = i + 1 < length ? BASE64.charCodeAt((b & 15) << 2) : 61;
    units[n++] = 61;
  }
  return n ? text + String.fromCharCode.apply(null, units.subarray(0, n)) : text;
};

function sextet(c) {
  return c >= 97 ? c - 71 : c >= 65 ? c - 65 : c >= 48 ? c + 4 : c === 43 ? 62 : 63;
}

var atob_ = function atob(data) {
  required(arguments, 1, 'atob');
  var s = toDOMString(data).replace(/[\t\n\f\r ]+/g, '');
  if (s.length % 4 === 0 && s.charCodeAt(s.length - 1) === 61) {
    s = s.slice(0, s.charCodeAt(s.length - 2) === 61 ? -2 : -1);
  }
  if (s.length % 4 === 1 || /[^A-Za-z0-9+\/]/.test(s)) {
    throw invalidCharacter('The string to be decoded is not correctly encoded.');
  }
  var length = s.length, units = new Uint16Array(Math.min(length, CHUNK) + 3), n = 0, text = '';
  var buffer = 0, bits = 0;
  for (var i = 0; i < length; i++) {
    buffer = (buffer << 6) | sextet(s.charCodeAt(i));
    bits += 6;
    if (bits === 24) {
      units[n++] = buffer >> 16;
      units[n++] = (buffer >> 8) & 0xFF;
      units[n++] = buffer & 0xFF;
      buffer = bits = 0;
      if (n >= CHUNK) {
        text += String.fromCharCode.apply(null, units.subarray(0, n));
        n = 0;
      }
    }
  }
  if (bits === 12) {
    units[n++] = buffer >> 4;
  } else if (bits === 18) {
    units[n++] = buffer >> 10;
    units[n++] = (buffer >> 2) & 0xFF;
  }
  return n ? text + String.fromCharCode.apply(null, units.subarray(0, n)) : text;
};

// ---- Percent-encoding ---------------------------------------------------

// The URL Standard's percent-encode sets, one bit each, for ASCII; every set
// holds the C0 controls, DEL and all that is past ASCII.
var C0 = 1, FRAGMENT = 2, QUERY = 4, SPECIAL_QUERY = 8, PATH = 16, USERINFO = 32, FORM = 64;
var encodeSets = null;

function setsOf(c) {
  if (encodeSets === null) {
    var t = new Uint8Array(128);
    var add = function (bits, chars) {
      for (var i = 0; i < chars.length; i++) t[chars.charCodeAt(i)] |= bits;
    };
    for (var c0 = 0; c0 < 0x20; c0++) t[c0] = 0xFF;
    t[0x7F] = 0xFF;
    add(FRAGMENT, ' "<>`');
    add(QUERY | SPECIAL_QUERY | PATH | USERINFO | FORM, ' "#<>');
    add(SPECIAL_QUERY, "'");
    add(PATH | USERINFO | FORM, '?^`{}');
    add(USERINFO | FORM, '/:;=@[\\]^|');
    add(FORM, "$%&+,!'()~");
    encodeSets = t;
  }
  return encodeSets[c];
}

var HEX = '0123456789ABCDEF';

function hexByte(b) {
  return '%' + HEX.charAt(b >> 4) + HEX.charAt(b & 15);
}

function encodeNonASCII(cp) {
  if (cp < 0x800) return hexByte(0xC0 | (cp >> 6)) + hexByte(0x80 | (cp & 0x3F));
  if (cp < 0x10000) return hexByte(0xE0 | (cp >> 12)) + hexByte(0x80 | ((cp >> 6) & 0x3F)) + hexByte(0x80 | (cp & 0x3F));
  return hexByte(0xF0 | (cp >> 18)) + hexByte(0x80 | ((cp >> 12) & 0x3F)) + hexByte(0x80 | ((cp >> 6) & 0x3F)) + hexByte(0x80 | (cp & 0x3F));
}

// UTF-8 percent-encodes the code point `c` (a string of one) with the set `bit`.
function encodeCodePoint(c, bit) {
  var cp = c.codePointAt(0);
  if (cp < 0x80) return setsOf(cp) & bit ? hexByte(cp) : c;
  return encodeNonASCII(cp);
}

// The same over a string; with `spaceAsPlus`, the form serializer's U+0020.
function encodeString(s, bit, spaceAsPlus) {
  var out = '', start = 0;
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i), piece;
    if (c < 0x80) {
      if (!(setsOf(c) & bit)) continue;
      piece = spaceAsPlus && c === 0x20 ? '+' : hexByte(c);
      out += s.slice(start, i) + piece;
      start = i + 1;
      continue;
    }
    var at = i;
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length && (s.charCodeAt(i + 1) & 0xFC00) === 0xDC00) {
      c = 0x10000 + ((c - 0xD800) << 10) + (s.charCodeAt(i + 1) - 0xDC00);
      i++;
    } else if (c >= 0xD800 && c <= 0xDFFF) {
      c = 0xFFFD;
    }
    out += s.slice(start, at) + encodeNonASCII(c);
    start = i + 1;
  }
  return start === 0 ? s : out + s.slice(start);
}

function isHexCode(b) {
  return (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66);
}

function hexValue(b) {
  return b <= 0x39 ? b - 0x30 : (b | 0x20) - 0x57;
}

// Percent-decodes the UTF-8 of `s`, then decodes that as UTF-8 without BOM.
function percentDecode(s) {
  if (s.indexOf('%') < 0) return s;
  var bytes = utf8Bytes(s), out = new Uint8Array(bytes.length), n = 0;
  for (var i = 0; i < bytes.length; i++) {
    var b = bytes[i];
    if (b === 0x25 && i + 2 < bytes.length && isHexCode(bytes[i + 1]) && isHexCode(bytes[i + 2])) {
      out[n++] = hexValue(bytes[i + 1]) * 16 + hexValue(bytes[i + 2]);
      i += 2;
    } else {
      out[n++] = b;
    }
  }
  return utf8DecodeReplacing(out.subarray(0, n));
}

// ---- application/x-www-form-urlencoded ----------------------------------

function parseForm(input) {
  var list = [], sequences = input.split('&');
  for (var i = 0; i < sequences.length; i++) {
    var sequence = sequences[i];
    if (sequence === '') continue;
    var eq = sequence.indexOf('=');
    var name = eq < 0 ? sequence : sequence.slice(0, eq);
    var value = eq < 0 ? '' : sequence.slice(eq + 1);
    list.push([percentDecode(name.replace(/\+/g, ' ')), percentDecode(value.replace(/\+/g, ' '))]);
  }
  return list;
}

function serializeForm(list) {
  var out = '';
  for (var i = 0; i < list.length; i++) {
    if (i) out += '&';
    out += encodeString(list[i][0], FORM, true) + '=' + encodeString(list[i][1], FORM, true);
  }
  return out;
}

// ---- Hosts ----------------------------------------------------------------

var FAILURE = {};

function parseIPv4Number(s) {
  if (s === '') return FAILURE;
  var radix = 10;
  if (s.length >= 2 && s.charAt(0) === '0' && (s.charAt(1) === 'x' || s.charAt(1) === 'X')) {
    s = s.slice(2);
    radix = 16;
  } else if (s.length >= 2 && s.charAt(0) === '0') {
    s = s.slice(1);
    radix = 8;
  }
  if (s === '') return 0;
  var valid = radix === 10 ? /^[0-9]+$/ : radix === 16 ? /^[0-9A-Fa-f]+$/ : /^[0-7]+$/;
  return valid.test(s) ? parseInt(s, radix) : FAILURE;
}

function endsInANumber(s) {
  var parts = s.split('.');
  if (parts[parts.length - 1] === '') {
    if (parts.length === 1) return false;
    parts.pop();
  }
  var last = parts[parts.length - 1];
  return /^[0-9]+$/.test(last) || parseIPv4Number(last) !== FAILURE;
}

function parseIPv4(s) {
  var parts = s.split('.');
  if (parts[parts.length - 1] === '' && parts.length > 1) parts.pop();
  if (parts.length > 4) return FAILURE;
  var numbers = [];
  for (var i = 0; i < parts.length; i++) {
    var number = parseIPv4Number(parts[i]);
    if (number === FAILURE) return FAILURE;
    numbers.push(number);
  }
  for (var j = 0; j < numbers.length - 1; j++) {
    if (numbers[j] > 255) return FAILURE;
  }
  if (numbers[numbers.length - 1] >= Math.pow(256, 5 - numbers.length)) return FAILURE;
  var address = numbers[numbers.length - 1];
  for (var k = 0; k < numbers.length - 1; k++) address += numbers[k] * Math.pow(256, 3 - k);
  return [address >>> 24, (address >>> 16) & 255, (address >>> 8) & 255, address & 255].join('.');
}

function isDigitAt(s, i) {
  var c = s.charCodeAt(i);
  return c >= 0x30 && c <= 0x39;
}

function parseIPv6(s) {
  var address = [0, 0, 0, 0, 0, 0, 0, 0];
  var pieceIndex = 0, compress = null, pointer = 0;
  if (s.charAt(pointer) === ':') {
    if (s.charAt(pointer + 1) !== ':') return FAILURE;
    pointer += 2;
    compress = ++pieceIndex;
  }
  while (pointer < s.length) {
    if (pieceIndex === 8) return FAILURE;
    if (s.charAt(pointer) === ':') {
      if (compress !== null) return FAILURE;
      pointer++;
      compress = ++pieceIndex;
      continue;
    }
    var value = 0, length = 0;
    while (length < 4 && pointer < s.length && isHexCode(s.charCodeAt(pointer))) {
      value = value * 16 + hexValue(s.charCodeAt(pointer));
      pointer++;
      length++;
    }
    if (s.charAt(pointer) === '.') {
      if (length === 0) return FAILURE;
      pointer -= length;
      if (pieceIndex > 6) return FAILURE;
      var numbersSeen = 0;
      while (pointer < s.length) {
        var piece = null;
        if (numbersSeen > 0) {
          if (s.charAt(pointer) === '.' && numbersSeen < 4) pointer++;
          else return FAILURE;
        }
        if (!isDigitAt(s, pointer)) return FAILURE;
        while (isDigitAt(s, pointer)) {
          var number = s.charCodeAt(pointer) - 0x30;
          if (piece === null) piece = number;
          else if (piece === 0) return FAILURE;
          else piece = piece * 10 + number;
          if (piece > 255) return FAILURE;
          pointer++;
        }
        address[pieceIndex] = address[pieceIndex] * 0x100 + piece;
        numbersSeen++;
        if (numbersSeen === 2 || numbersSeen === 4) pieceIndex++;
      }
      if (numbersSeen !== 4) return FAILURE;
      break;
    } else if (s.charAt(pointer) === ':') {
      pointer++;
      if (pointer >= s.length) return FAILURE;
    } else if (pointer < s.length) {
      return FAILURE;
    }
    address[pieceIndex] = value;
    pieceIndex++;
  }
  if (compress !== null) {
    var swaps = pieceIndex - compress;
    pieceIndex = 7;
    while (pieceIndex !== 0 && swaps > 0) {
      var swapped = address[pieceIndex];
      address[pieceIndex] = address[compress + swaps - 1];
      address[compress + swaps - 1] = swapped;
      pieceIndex--;
      swaps--;
    }
  } else if (pieceIndex !== 8) {
    return FAILURE;
  }
  return address;
}

function serializeIPv6(address) {
  var compress = null, longest = 1;
  for (var i = 0; i < 8;) {
    if (address[i] !== 0) { i++; continue; }
    var end = i;
    while (end < 8 && address[end] === 0) end++;
    if (end - i > longest) { longest = end - i; compress = i; }
    i = end;
  }
  var out = '', ignore0 = false;
  for (var p = 0; p < 8; p++) {
    if (ignore0 && address[p] === 0) continue;
    ignore0 = false;
    if (compress === p) {
      out += p === 0 ? '::' : ':';
      ignore0 = true;
      continue;
    }
    out += address[p].toString(16);
    if (p !== 7) out += ':';
  }
  return out;
}

var FORBIDDEN_HOST = /[\u0000\t\n\r #\/:<>?@\[\\\]^|]/;
var FORBIDDEN_DOMAIN = /[\u0000-\u0020#%\/:<>?@\[\\\]^|\u007F]/;

// A host, serialized: a domain, an IPv4 or [IPv6] address, an opaque host,
// or '' (the empty host).
function parseHost(input, isOpaque) {
  if (input.charAt(0) === '[') {
    if (input.charAt(input.length - 1) !== ']') return FAILURE;
    var address = parseIPv6(input.slice(1, -1));
    return address === FAILURE ? FAILURE : '[' + serializeIPv6(address) + ']';
  }
  if (isOpaque) return FORBIDDEN_HOST.test(input) ? FAILURE : encodeString(input, C0, false);
  var domain = percentDecode(input);
  // No IDNA (R-173): what is not ASCII cannot be made a domain here.
  if (/[^\u0000-\u007F]/.test(domain)) return FAILURE;
  domain = domain.toLowerCase();
  if (domain === '' || FORBIDDEN_DOMAIN.test(domain)) return FAILURE;
  return endsInANumber(domain) ? parseIPv4(domain) : domain;
}

// ---- The basic URL parser -----------------------------------------------

var SCHEME_START = 1, SCHEME = 2, NO_SCHEME = 3, SPECIAL_RELATIVE_OR_AUTHORITY = 4, PATH_OR_AUTHORITY = 5,
  RELATIVE = 6, RELATIVE_SLASH = 7, SPECIAL_AUTHORITY_SLASHES = 8, SPECIAL_AUTHORITY_IGNORE_SLASHES = 9,
  AUTHORITY = 10, HOST = 11, HOSTNAME = 12, PORT = 13, FILE = 14, FILE_SLASH = 15, FILE_HOST = 16,
  PATH_START = 17, PATH_STATE = 18, OPAQUE_PATH = 19, QUERY_STATE = 20, FRAGMENT_STATE = 21;

function isSpecialScheme(scheme) {
  switch (scheme) {
    case 'ftp': case 'file': case 'http': case 'https': case 'ws': case 'wss': return true;
    default: return false;
  }
}

function defaultPort(scheme) {
  switch (scheme) {
    case 'ftp': return 21;
    case 'http': case 'ws': return 80;
    case 'https': case 'wss': return 443;
    default: return null;
  }
}

function newRecord() {
  return { scheme: '', username: '', password: '', host: null, port: null, path: [], query: null, fragment: null };
}

function hasOpaquePath(url) {
  return typeof url.path === 'string';
}

function includesCredentials(url) {
  return url.username !== '' || url.password !== '';
}

function cannotHaveCredentialsOrPort(url) {
  return url.host === null || url.host === '' || url.scheme === 'file';
}

function isAlpha(c) {
  return c !== undefined && ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'));
}

function isWindowsDriveLetter(s) {
  return s.length === 2 && isAlpha(s.charAt(0)) && (s.charAt(1) === ':' || s.charAt(1) === '|');
}

function isNormalizedWindowsDriveLetter(s) {
  return s.length === 2 && isAlpha(s.charAt(0)) && s.charAt(1) === ':';
}

function startsWithWindowsDriveLetter(cps, pointer) {
  if (cps.length - pointer < 2 || !isAlpha(cps[pointer]) || (cps[pointer + 1] !== ':' && cps[pointer + 1] !== '|')) return false;
  var third = cps[pointer + 2];
  return third === undefined || third === '/' || third === '\\' || third === '?' || third === '#';
}

function isSingleDot(s) {
  return s === '.' || s.toLowerCase() === '%2e';
}

function isDoubleDot(s) {
  switch (s.toLowerCase()) {
    case '..': case '.%2e': case '%2e.': case '%2e%2e': return true;
    default: return false;
  }
}

function shortenPath(url) {
  var path = url.path;
  if (url.scheme === 'file' && path.length === 1 && isNormalizedWindowsDriveLetter(path[0])) return;
  path.pop();
}

// https://url.spec.whatwg.org/#concept-basic-url-parser, with `url` and
// `override` for the setters. Returns the record, or FAILURE.
function basicParse(input, base, url, override) {
  if (!url) {
    url = newRecord();
    input = input.replace(/^[\u0000-\u0020]+|[\u0000-\u0020]+$/g, '');
  }
  input = input.replace(/[\t\n\r]/g, '');
  var cps = Array.from(input);
  var state = override || SCHEME_START;
  var buffer = '', atSignSeen = false, insideBrackets = false, passwordTokenSeen = false;
  for (var pointer = 0; ; pointer++) {
    var c = cps[pointer];
    var special = isSpecialScheme(url.scheme);
    var host;
    switch (state) {
      case SCHEME_START:
        if (isAlpha(c)) {
          buffer += c.toLowerCase();
          state = SCHEME;
        } else if (!override) {
          state = NO_SCHEME;
          pointer--;
        } else {
          return FAILURE;
        }
        break;

      case SCHEME:
        if (c !== undefined && (isAlpha(c) || (c >= '0' && c <= '9') || c === '+' || c === '-' || c === '.')) {
          buffer += c.toLowerCase();
        } else if (c === ':') {
          if (override) {
            if (special !== isSpecialScheme(buffer)) return url;
            if ((includesCredentials(url) || url.port !== null) && buffer === 'file') return url;
            if (url.scheme === 'file' && url.host === '') return url;
          }
          url.scheme = buffer;
          if (override) {
            if (url.port === defaultPort(url.scheme)) url.port = null;
            return url;
          }
          buffer = '';
          if (url.scheme === 'file') {
            state = FILE;
          } else if (isSpecialScheme(url.scheme) && base && base.scheme === url.scheme) {
            state = SPECIAL_RELATIVE_OR_AUTHORITY;
          } else if (isSpecialScheme(url.scheme)) {
            state = SPECIAL_AUTHORITY_SLASHES;
          } else if (cps[pointer + 1] === '/') {
            state = PATH_OR_AUTHORITY;
            pointer++;
          } else {
            url.path = '';
            state = OPAQUE_PATH;
          }
        } else if (!override) {
          buffer = '';
          state = NO_SCHEME;
          pointer = -1;
        } else {
          return FAILURE;
        }
        break;

      case NO_SCHEME:
        if (!base || (hasOpaquePath(base) && c !== '#')) return FAILURE;
        if (hasOpaquePath(base) && c === '#') {
          url.scheme = base.scheme;
          url.path = base.path;
          url.query = base.query;
          url.fragment = '';
          state = FRAGMENT_STATE;
        } else if (base.scheme !== 'file') {
          state = RELATIVE;
          pointer--;
        } else {
          state = FILE;
          pointer--;
        }
        break;

      case SPECIAL_RELATIVE_OR_AUTHORITY:
        if (c === '/' && cps[pointer + 1] === '/') {
          state = SPECIAL_AUTHORITY_IGNORE_SLASHES;
          pointer++;
        } else {
          state = RELATIVE;
          pointer--;
        }
        break;

      case PATH_OR_AUTHORITY:
        if (c === '/') {
          state = AUTHORITY;
        } else {
          state = PATH_STATE;
          pointer--;
        }
        break;

      case RELATIVE:
        url.scheme = base.scheme;
        if (c === '/' || (isSpecialScheme(url.scheme) && c === '\\')) {
          state = RELATIVE_SLASH;
        } else {
          url.username = base.username;
          url.password = base.password;
          url.host = base.host;
          url.port = base.port;
          url.path = base.path.slice();
          url.query = base.query;
          if (c === '?') {
            url.query = '';
            state = QUERY_STATE;
          } else if (c === '#') {
            url.fragment = '';
            state = FRAGMENT_STATE;
          } else if (c !== undefined) {
            url.query = null;
            shortenPath(url);
            state = PATH_STATE;
            pointer--;
          }
        }
        break;

      case RELATIVE_SLASH:
        if (special && (c === '/' || c === '\\')) {
          state = SPECIAL_AUTHORITY_IGNORE_SLASHES;
        } else if (c === '/') {
          state = AUTHORITY;
        } else {
          url.username = base.username;
          url.password = base.password;
          url.host = base.host;
          url.port = base.port;
          state = PATH_STATE;
          pointer--;
        }
        break;

      case SPECIAL_AUTHORITY_SLASHES:
        state = SPECIAL_AUTHORITY_IGNORE_SLASHES;
        if (c === '/' && cps[pointer + 1] === '/') pointer++;
        else pointer--;
        break;

      case SPECIAL_AUTHORITY_IGNORE_SLASHES:
        if (c !== '/' && c !== '\\') {
          state = AUTHORITY;
          pointer--;
        }
        break;

      case AUTHORITY:
        if (c === '@') {
          if (atSignSeen) buffer = '%40' + buffer;
          atSignSeen = true;
          var credentials = Array.from(buffer);
          for (var k = 0; k < credentials.length; k++) {
            if (credentials[k] === ':' && !passwordTokenSeen) {
              passwordTokenSeen = true;
              continue;
            }
            var encoded = encodeCodePoint(credentials[k], USERINFO);
            if (passwordTokenSeen) url.password += encoded;
            else url.username += encoded;
          }
          buffer = '';
        } else if (c === undefined || c === '/' || c === '?' || c === '#' || (special && c === '\\')) {
          if (atSignSeen && buffer === '') return FAILURE;
          pointer -= Array.from(buffer).length + 1;
          buffer = '';
          state = HOST;
        } else {
          buffer += c;
        }
        break;

      case HOST:
      case HOSTNAME:
        if (override && url.scheme === 'file') {
          pointer--;
          state = FILE_HOST;
        } else if (c === ':' && !insideBrackets) {
          if (buffer === '') return FAILURE;
          if (override === HOSTNAME) return FAILURE;
          host = parseHost(buffer, !special);
          if (host === FAILURE) return FAILURE;
          url.host = host;
          buffer = '';
          state = PORT;
        } else if (c === undefined || c === '/' || c === '?' || c === '#' || (special && c === '\\')) {
          pointer--;
          if (special && buffer === '') return FAILURE;
          if (override && buffer === '' && (includesCredentials(url) || url.port !== null)) return FAILURE;
          host = parseHost(buffer, !special);
          if (host === FAILURE) return FAILURE;
          url.host = host;
          buffer = '';
          state = PATH_START;
          if (override) return url;
        } else {
          if (c === '[') insideBrackets = true;
          if (c === ']') insideBrackets = false;
          buffer += c;
        }
        break;

      case PORT:
        if (c !== undefined && c >= '0' && c <= '9') {
          buffer += c;
        } else if (c === undefined || c === '/' || c === '?' || c === '#' || (special && c === '\\') || override) {
          if (buffer !== '') {
            var port = parseInt(buffer, 10);
            if (port > 65535) return FAILURE;
            url.port = port === defaultPort(url.scheme) ? null : port;
            buffer = '';
            if (override) return url;
          }
          if (override) return FAILURE;
          state = PATH_START;
          pointer--;
        } else {
          return FAILURE;
        }
        break;

      case FILE:
        url.scheme = 'file';
        url.host = '';
        if (c === '/' || c === '\\') {
          state = FILE_SLASH;
        } else if (base && base.scheme === 'file') {
          url.host = base.host;
          url.path = base.path.slice();
          url.query = base.query;
          if (c === '?') {
            url.query = '';
            state = QUERY_STATE;
          } else if (c === '#') {
            url.fragment = '';
            state = FRAGMENT_STATE;
          } else if (c !== undefined) {
            url.query = null;
            if (!startsWithWindowsDriveLetter(cps, pointer)) shortenPath(url);
            else url.path = [];
            state = PATH_STATE;
            pointer--;
          }
        } else {
          state = PATH_STATE;
          pointer--;
        }
        break;

      case FILE_SLASH:
        if (c === '/' || c === '\\') {
          state = FILE_HOST;
        } else {
          if (base && base.scheme === 'file') {
            url.host = base.host;
            if (!startsWithWindowsDriveLetter(cps, pointer) && base.path.length > 0 && isNormalizedWindowsDriveLetter(base.path[0])) {
              url.path.push(base.path[0]);
            }
          }
          state = PATH_STATE;
          pointer--;
        }
        break;

      case FILE_HOST:
        if (c === undefined || c === '/' || c === '\\' || c === '?' || c === '#') {
          pointer--;
          if (!override && isWindowsDriveLetter(buffer)) {
            state = PATH_STATE;
          } else if (buffer === '') {
            url.host = '';
            if (override) return url;
            state = PATH_START;
          } else {
            host = parseHost(buffer, !special);
            if (host === FAILURE) return FAILURE;
            url.host = host === 'localhost' ? '' : host;
            if (override) return url;
            buffer = '';
            state = PATH_START;
          }
        } else {
          buffer += c;
        }
        break;

      case PATH_START:
        if (special) {
          state = PATH_STATE;
          if (c !== '/' && c !== '\\') pointer--;
        } else if (!override && c === '?') {
          url.query = '';
          state = QUERY_STATE;
        } else if (!override && c === '#') {
          url.fragment = '';
          state = FRAGMENT_STATE;
        } else if (c !== undefined) {
          state = PATH_STATE;
          if (c !== '/') pointer--;
        } else if (override && url.host === null) {
          url.path.push('');
        }
        break;

      case PATH_STATE:
        var slash = c === '/' || (special && c === '\\');
        if (c === undefined || slash || (!override && (c === '?' || c === '#'))) {
          if (isDoubleDot(buffer)) {
            shortenPath(url);
            if (!slash) url.path.push('');
          } else if (isSingleDot(buffer)) {
            if (!slash) url.path.push('');
          } else {
            if (url.scheme === 'file' && url.path.length === 0 && isWindowsDriveLetter(buffer)) buffer = buffer.charAt(0) + ':';
            url.path.push(buffer);
          }
          buffer = '';
          if (c === '?') {
            url.query = '';
            state = QUERY_STATE;
          } else if (c === '#') {
            url.fragment = '';
            state = FRAGMENT_STATE;
          }
        } else {
          buffer += encodeCodePoint(c, PATH);
        }
        break;

      case OPAQUE_PATH:
        if (c === '?') {
          url.query = '';
          state = QUERY_STATE;
        } else if (c === '#') {
          url.fragment = '';
          state = FRAGMENT_STATE;
        } else if (c === ' ') {
          // A space before the query or fragment is written %20, so that no
          // opaque path ends in a space once they are gone.
          url.path += cps[pointer + 1] === '?' || cps[pointer + 1] === '#' ? '%20' : ' ';
        } else if (c !== undefined) {
          url.path += encodeCodePoint(c, C0);
        }
        break;

      case QUERY_STATE:
        if ((!override && c === '#') || c === undefined) {
          url.query += encodeString(buffer, special ? SPECIAL_QUERY : QUERY, false);
          buffer = '';
          if (c === '#') {
            url.fragment = '';
            state = FRAGMENT_STATE;
          }
        } else {
          buffer += c;
        }
        break;

      case FRAGMENT_STATE:
        if (c !== undefined) url.fragment += encodeCodePoint(c, FRAGMENT);
        break;
    }
    if (pointer >= cps.length) return url;
  }
}

function parseURL(input, base) {
  return basicParse(input, base, null, 0);
}

function serializePath(url) {
  if (hasOpaquePath(url)) return url.path;
  var out = '';
  for (var i = 0; i < url.path.length; i++) out += '/' + url.path[i];
  return out;
}

function serializeURL(url) {
  var out = url.scheme + ':';
  if (url.host !== null) {
    out += '//';
    if (includesCredentials(url)) {
      out += url.username;
      if (url.password !== '') out += ':' + url.password;
      out += '@';
    }
    out += url.host;
    if (url.port !== null) out += ':' + url.port;
  } else if (!hasOpaquePath(url) && url.path.length > 1 && url.path[0] === '') {
    out += '/.';
  }
  out += serializePath(url);
  if (url.query !== null) out += '?' + url.query;
  if (url.fragment !== null) out += '#' + url.fragment;
  return out;
}

function originOf(url) {
  switch (url.scheme) {
    case 'blob':
      var inner = parseURL(serializePath(url));
      return inner !== FAILURE && (inner.scheme === 'http' || inner.scheme === 'https') ? originOf(inner) : 'null';
    case 'ftp': case 'http': case 'https': case 'ws': case 'wss':
      return url.scheme + '://' + url.host + (url.port === null ? '' : ':' + url.port);
    default:
      return 'null';
  }
}

// ---- URLSearchParams ----------------------------------------------------

// A URL's state is { url: its record, query: its URLSearchParams or null
// until asked for, stale: true while the record's query lags its list }; a
// URLSearchParams' is { list, owner: that URL state or null }.
var urls = new WeakMap();
var searches = new WeakMap();
var iterators = new WeakMap();

// Every way into a URL comes through here, so a record whose query lags its
// list is brought up to date before anything reads or writes it.
function urlState(self) {
  var state = urls.get(self);
  if (state === undefined) throw new TypeError('Illegal invocation');
  if (state.stale) {
    state.stale = false;
    var serialized = serializeForm(searchState(state.query).list);
    state.url.query = serialized === '' ? null : serialized;
  }
  return state;
}

function searchState(self) {
  var state = searches.get(self);
  if (state === undefined) throw new TypeError('Illegal invocation');
  return state;
}

// The update steps: the owner's query becomes the list, serialized -- when
// the URL is next used (urlState), so a run of edits serializes once, not
// once each.
function update(state) {
  if (state.owner !== null) state.owner.stale = true;
}

function resetQuery(state) {
  if (state.query !== null) searchState(state.query).list = state.url.query === null ? [] : parseForm(state.url.query);
}

var iteratorPrototype = Object.create(Object.getPrototypeOf(Object.getPrototypeOf([][Symbol.iterator]())));
Object.defineProperty(iteratorPrototype, 'next', {
  value: function next() {
    var it = iterators.get(this);
    if (it === undefined) throw new TypeError('Illegal invocation');
    var list = it.state.list;
    if (it.index >= list.length) return { value: undefined, done: true };
    var pair = list[it.index++];
    return { value: it.kind === 0 ? pair[0] : it.kind === 1 ? pair[1] : [pair[0], pair[1]], done: false };
  },
  writable: true, enumerable: true, configurable: true
});
Object.defineProperty(iteratorPrototype, Symbol.toStringTag, { value: 'URLSearchParams Iterator', configurable: true });

function iterate(self, kind) {
  var it = Object.create(iteratorPrototype);
  iterators.set(it, { state: searchState(self), kind: kind, index: 0 });
  return it;
}

var Search = class URLSearchParams {
  constructor(init = undefined) {
    var list = [];
    if (isObject(init)) {
      var method = init[Symbol.iterator];
      if (method !== undefined && method !== null) {
        if (typeof method !== 'function') throw new TypeError("URLSearchParams: the value's @@iterator is not a function");
        for (var pair of init) {
          if (!isObject(pair) || typeof pair[Symbol.iterator] !== 'function') {
            throw new TypeError('URLSearchParams: each item must be a sequence of a name and a value');
          }
          var items = Array.from(pair);
          if (items.length !== 2) throw new TypeError('URLSearchParams: each item must be a name and a value');
          list.push([toUSV(items[0]), toUSV(items[1])]);
        }
      } else {
        var keys = Object.keys(init);
        for (var i = 0; i < keys.length; i++) list.push([toUSV(keys[i]), toUSV(init[keys[i]])]);
      }
    } else if (init !== undefined) {
      var s = toUSV(init);
      list = parseForm(s.charAt(0) === '?' ? s.slice(1) : s);
    }
    searches.set(this, { list: list, owner: null });
  }
  get size() {
    return searchState(this).list.length;
  }
  append(name, value) {
    var state = searchState(this);
    required(arguments, 2, 'append');
    state.list.push([toUSV(name), toUSV(value)]);
    update(state);
  }
  delete(name, value = undefined) {
    var state = searchState(this);
    required(arguments, 1, 'delete');
    var n = toUSV(name), v = value === undefined ? undefined : toUSV(value);
    state.list = state.list.filter(function (pair) { return pair[0] !== n || (v !== undefined && pair[1] !== v); });
    update(state);
  }
  get(name) {
    var state = searchState(this);
    required(arguments, 1, 'get');
    var n = toUSV(name);
    for (var i = 0; i < state.list.length; i++) if (state.list[i][0] === n) return state.list[i][1];
    return null;
  }
  getAll(name) {
    var state = searchState(this);
    required(arguments, 1, 'getAll');
    var n = toUSV(name), out = [];
    for (var i = 0; i < state.list.length; i++) if (state.list[i][0] === n) out.push(state.list[i][1]);
    return out;
  }
  has(name, value = undefined) {
    var state = searchState(this);
    required(arguments, 1, 'has');
    var n = toUSV(name), v = value === undefined ? undefined : toUSV(value);
    for (var i = 0; i < state.list.length; i++) {
      if (state.list[i][0] === n && (v === undefined || state.list[i][1] === v)) return true;
    }
    return false;
  }
  set(name, value) {
    var state = searchState(this);
    required(arguments, 2, 'set');
    var n = toUSV(name), v = toUSV(value), found = false;
    state.list = state.list.filter(function (pair) {
      if (pair[0] !== n) return true;
      if (found) return false;
      found = true;
      pair[1] = v;
      return true;
    });
    if (!found) state.list.push([n, v]);
    update(state);
  }
  sort() {
    var state = searchState(this);
    state.list.sort(function (a, b) { return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0; });
    update(state);
  }
  forEach(callback, thisArg = undefined) {
    var state = searchState(this);
    required(arguments, 1, 'forEach');
    if (typeof callback !== 'function') throw new TypeError('forEach: the callback is not a function');
    for (var i = 0; i < state.list.length; i++) callback.call(thisArg, state.list[i][1], state.list[i][0], this);
  }
  keys() { return iterate(this, 0); }
  values() { return iterate(this, 1); }
  entries() { return iterate(this, 2); }
  toString() {
    return serializeForm(searchState(this).list);
  }
};
expose(Search, 'URLSearchParams');
Object.defineProperty(Search.prototype, Symbol.iterator, { value: Search.prototype.entries, writable: true, configurable: true });

// ---- URL ------------------------------------------------------------------

function parseArguments(url, base) {
  var baseRecord;
  if (base !== undefined) {
    baseRecord = parseURL(toUSV(base));
    if (baseRecord === FAILURE) return FAILURE;
  }
  return parseURL(toUSV(url), baseRecord);
}

var Locator = class URL {
  constructor(url, base = undefined) {
    required(arguments, 1, 'URL');
    var record = parseArguments(url, base);
    if (record === FAILURE) throw new TypeError('Invalid URL: ' + toUSV(url));
    urls.set(this, { url: record, query: null });
  }
  static canParse(url, base = undefined) {
    required(arguments, 1, 'canParse');
    return parseArguments(url, base) !== FAILURE;
  }
  static parse(url, base = undefined) {
    required(arguments, 1, 'parse');
    var record = parseArguments(url, base);
    if (record === FAILURE) return null;
    var made = Object.create(Locator.prototype);
    urls.set(made, { url: record, query: null });
    return made;
  }
  get href() { return serializeURL(urlState(this).url); }
  set href(value) {
    var state = urlState(this);
    var record = parseURL(toUSV(value));
    if (record === FAILURE) throw new TypeError('Invalid URL: ' + toUSV(value));
    state.url = record;
    resetQuery(state);
  }
  get origin() { return originOf(urlState(this).url); }
  get protocol() { return urlState(this).url.scheme + ':'; }
  set protocol(value) { basicParse(toUSV(value) + ':', null, urlState(this).url, SCHEME_START); }
  get username() { return urlState(this).url.username; }
  set username(value) {
    var url = urlState(this).url;
    if (!cannotHaveCredentialsOrPort(url)) url.username = encodeString(toUSV(value), USERINFO, false);
  }
  get password() { return urlState(this).url.password; }
  set password(value) {
    var url = urlState(this).url;
    if (!cannotHaveCredentialsOrPort(url)) url.password = encodeString(toUSV(value), USERINFO, false);
  }
  get host() {
    var url = urlState(this).url;
    if (url.host === null) return '';
    return url.port === null ? url.host : url.host + ':' + url.port;
  }
  set host(value) {
    var url = urlState(this).url;
    if (!hasOpaquePath(url)) basicParse(toUSV(value), null, url, HOST);
  }
  get hostname() {
    var host = urlState(this).url.host;
    return host === null ? '' : host;
  }
  set hostname(value) {
    var url = urlState(this).url;
    if (!hasOpaquePath(url)) basicParse(toUSV(value), null, url, HOSTNAME);
  }
  get port() {
    var port = urlState(this).url.port;
    return port === null ? '' : String(port);
  }
  set port(value) {
    var url = urlState(this).url;
    if (cannotHaveCredentialsOrPort(url)) return;
    var s = toUSV(value);
    if (s === '') url.port = null;
    else basicParse(s, null, url, PORT);
  }
  get pathname() { return serializePath(urlState(this).url); }
  set pathname(value) {
    var url = urlState(this).url;
    if (hasOpaquePath(url)) return;
    url.path = [];
    basicParse(toUSV(value), null, url, PATH_START);
  }
  get search() {
    var query = urlState(this).url.query;
    return query === null || query === '' ? '' : '?' + query;
  }
  set search(value) {
    var state = urlState(this), url = state.url, s = toUSV(value);
    if (s === '') {
      url.query = null;
      resetQuery(state);
      return;
    }
    if (s.charAt(0) === '?') s = s.slice(1);
    url.query = '';
    basicParse(s, null, url, QUERY_STATE);
    if (state.query !== null) searchState(state.query).list = parseForm(s);
  }
  get searchParams() {
    var state = urlState(this);
    if (state.query === null) {
      var query = Object.create(Search.prototype);
      searches.set(query, { list: state.url.query === null ? [] : parseForm(state.url.query), owner: state });
      state.query = query;
    }
    return state.query;
  }
  get hash() {
    var fragment = urlState(this).url.fragment;
    return fragment === null || fragment === '' ? '' : '#' + fragment;
  }
  set hash(value) {
    var url = urlState(this).url, s = toUSV(value);
    if (s === '') {
      url.fragment = null;
      return;
    }
    if (s.charAt(0) === '#') s = s.slice(1);
    url.fragment = '';
    basicParse(s, null, url, FRAGMENT_STATE);
  }
  toString() { return serializeURL(urlState(this).url); }
  toJSON() { return serializeURL(urlState(this).url); }
};
expose(Locator, 'URL');

// ---- structuredClone ----------------------------------------------------
// HTML's structured clone (https://html.spec.whatwg.org/#structured-cloning)
// for what a script holds; Loon 3.5.2 defines it. Primitives but
// symbols; the Boolean, Number, String and BigInt wrappers; Date; RegExp;
// ArrayBuffer, its typed arrays and DataView (a buffer two views share stays
// shared); Map and Set; the errors (name and message); arrays and other
// objects by their own enumerable string keys, a prototype not kept -- each
// told by what it is, not by what its toStringTag says. The same object
// twice, or a cycle, stays one object. Anything else -- a function, a symbol,
// an object an interface made (these globals', or one marked as the host's)
// -- is a DataCloneError (code 25), as the DOMException would be; so is a
// non-empty `transfer`, not supported.

function dataCloneError(what) {
  var error = new Error(what + ' could not be cloned.');
  Object.defineProperty(error, 'name', { value: 'DataCloneError', writable: true, configurable: true });
  Object.defineProperty(error, 'code', { value: 25, writable: true, configurable: true });
  return error;
}

var ERROR_NAMES = ['Error', 'EvalError', 'RangeError', 'ReferenceError', 'SyntaxError', 'TypeError', 'URIError'];
var VIEWS = { Int8Array: Int8Array, Uint8Array: Uint8Array, Uint8ClampedArray: Uint8ClampedArray, Int16Array: Int16Array,
              Uint16Array: Uint16Array, Int32Array: Int32Array, Uint32Array: Uint32Array, Float32Array: Float32Array,
              Float64Array: Float64Array };
if (typeof BigInt64Array === 'function') VIEWS.BigInt64Array = BigInt64Array;
if (typeof BigUint64Array === 'function') VIEWS.BigUint64Array = BigUint64Array;

// What a value is, by the internal slot a built-in's own method checks
// (calling it on anything else throws), never by Symbol.toStringTag, which
// any object may set: an object that calls itself a Map is an object.
function brand(call) { try { call(); return true; } catch (e) { return false; } }
var getter = function (object, key) { return Object.getOwnPropertyDescriptor(object, key).get; };
var typedArrayName = getter(Object.getPrototypeOf(Int8Array.prototype), Symbol.toStringTag);
var bufferLength = getter(ArrayBuffer.prototype, 'byteLength');
var viewLength = getter(DataView.prototype, 'byteLength');
var regExpSource = getter(RegExp.prototype, 'source');
function kindOf(v) {
  if (Array.isArray(v)) return 'Array';
  var view = typedArrayName.call(v);
  if (view !== undefined) return view;
  if (brand(function () { viewLength.call(v); })) return 'DataView';
  if (brand(function () { bufferLength.call(v); })) return 'ArrayBuffer';
  if (brand(function () { Map.prototype.has.call(v, undefined); })) return 'Map';
  if (brand(function () { Set.prototype.has.call(v, undefined); })) return 'Set';
  if (brand(function () { Date.prototype.getTime.call(v); })) return 'Date';
  if (v !== RegExp.prototype && brand(function () { regExpSource.call(v); })) return 'RegExp';
  if (brand(function () { Boolean.prototype.valueOf.call(v); })) return 'Boolean';
  if (brand(function () { Number.prototype.valueOf.call(v); })) return 'Number';
  if (brand(function () { String.prototype.valueOf.call(v); })) return 'String';
  if (typeof BigInt === 'function' && brand(function () { BigInt.prototype.valueOf.call(v); })) return 'BigInt';
  if (v instanceof Error) return 'Error';
  // The objects these globals (and the host) make stand for a platform's,
  // which no structured clone copies.
  if (v[PLATFORM_OBJECT] === true || v instanceof Encoder || v instanceof Decoder || v instanceof Locator || v instanceof Search) {
    return 'Platform';
  }
  return 'Object';
}

// The host's other platform objects (a parsed document's nodes) say so with
// this mark on their prototype.
var PLATFORM_OBJECT = Symbol.for('clash.platformObject');

var structuredClone_ = function structuredClone(value) {
  required(arguments, 1, 'structuredClone');
  var options = arguments[1];
  if (options !== undefined && options !== null) {
    var transfer = options.transfer;
    if (transfer !== undefined && transfer !== null && Array.from(transfer).length > 0) {
      throw dataCloneError('A transfer list');
    }
  }
  var memory = new Map();
  function keep(original, copy) { memory.set(original, copy); return copy; }
  function members(original, copy) {
    Object.keys(original).forEach(function (key) { copy[key] = clone(original[key]); });
    return copy;
  }
  function clone(v) {
    var type = typeof v;
    if (v === null || type === 'undefined' || type === 'boolean' || type === 'number' || type === 'string' || type === 'bigint') {
      return v;
    }
    if (type === 'symbol') throw dataCloneError('A Symbol');
    if (type === 'function') throw dataCloneError('A function');
    if (memory.has(v)) return memory.get(v);
    var kind = kindOf(v);
    switch (kind) {
      case 'Boolean': return keep(v, Object(Boolean.prototype.valueOf.call(v)));
      case 'Number': return keep(v, Object(Number.prototype.valueOf.call(v)));
      case 'String': return keep(v, Object(String.prototype.valueOf.call(v)));
      case 'BigInt': return keep(v, Object(BigInt.prototype.valueOf.call(v)));
      case 'Date': return keep(v, new Date(Date.prototype.getTime.call(v)));
      case 'RegExp': return keep(v, new RegExp(regExpSource.call(v), getter(RegExp.prototype, 'flags').call(v)));
      case 'ArrayBuffer': return keep(v, ArrayBuffer.prototype.slice.call(v, 0));
      case 'DataView': {
        var buffer = getter(DataView.prototype, 'buffer').call(v);
        return keep(v, new DataView(clone(buffer), getter(DataView.prototype, 'byteOffset').call(v), viewLength.call(v)));
      }
      case 'Map': {
        var map = keep(v, new Map());
        Map.prototype.forEach.call(v, function (item, key) { map.set(clone(key), clone(item)); });
        return map;
      }
      case 'Set': {
        var set = keep(v, new Set());
        Set.prototype.forEach.call(v, function (item) { set.add(clone(item)); });
        return set;
      }
      case 'Error': {
        var name = ERROR_NAMES.indexOf(v.name) >= 0 ? v.name : 'Error';
        var error = keep(v, new global[name]());
        var message = Object.getOwnPropertyDescriptor(v, 'message');
        if (message && 'value' in message) {
          Object.defineProperty(error, 'message', { value: String(message.value), writable: true, configurable: true });
        }
        return error;
      }
      case 'Array': return members(v, keep(v, new Array(v.length)));
      case 'Object': return members(v, keep(v, {}));
      case 'Platform': throw dataCloneError('#<' + Object.prototype.toString.call(v).slice(8, -1) + '>');
    }
    var typed = getter(Object.getPrototypeOf(Int8Array.prototype), 'buffer');
    return keep(v, new VIEWS[kind](clone(typed.call(v)), getter(Object.getPrototypeOf(Int8Array.prototype), 'byteOffset').call(v),
                                    getter(Object.getPrototypeOf(Int8Array.prototype), 'length').call(v)));
  }
  return clone(value);
};

// ---- What JavaScriptCore before iOS 15.4 lacks ---------------------------

// Object.hasOwn and the `at` of arrays, strings and typed arrays (ES2022),
// and the findLast and findLastIndex of arrays and typed arrays (ES2023),
// which scripts call with no fallback: each defined only where it is missing,
// as a built-in is (not enumerable), and as the specification writes it.

function toIntegerOrInfinity(value) {
  var number = +value;
  return number !== number || number === 0 ? 0 : Math.trunc(number);
}

// The index `at` reads, or -1 when it is out of range.
function relativeIndex(index, length) {
  var relative = toIntegerOrInfinity(index);
  var k = relative >= 0 ? relative : length + relative;
  return k < 0 || k >= length ? -1 : k;
}

function fillIn(object, name, value) {
  if (typeof object[name] === 'undefined') {
    Object.defineProperty(object, name, { value: value, writable: true, enumerable: false, configurable: true });
  }
}

var hasOwnProperty = Object.prototype.hasOwnProperty;
var TypedArrayPrototype = Object.getPrototypeOf(Int8Array.prototype);
var typedArrayLength = Object.getOwnPropertyDescriptor(TypedArrayPrototype, 'length').get;
var typedArrayBuffer = Object.getOwnPropertyDescriptor(TypedArrayPrototype, 'buffer').get;

fillIn(Object, 'hasOwn', function hasOwn(object, key) {
  if (object === null || object === undefined) throw new TypeError('Cannot convert undefined or null to object');
  return hasOwnProperty.call(object, key);
});

fillIn(Array.prototype, 'at', function at(index) {
  if (this === null || this === undefined) throw new TypeError('Array.prototype.at called on null or undefined');
  var object = Object(this);
  var k = relativeIndex(index, lengthOfArrayLike(object));
  return k < 0 ? undefined : object[k];
});

fillIn(String.prototype, 'at', function at(index) {
  if (this === null || this === undefined) throw new TypeError('String.prototype.at called on null or undefined');
  var s = toDOMString(this);
  var k = relativeIndex(index, s.length);
  return k < 0 ? undefined : s.charAt(k);
});

// A length clamped as LengthOfArrayLike clamps it.
function lengthOfArrayLike(object) {
  var length = toIntegerOrInfinity(object.length);
  return length <= 0 ? 0 : Math.min(length, 9007199254740991);
}

// ValidateTypedArray: the length of `self`, a typed array whose buffer is not detached.
function validTypedArrayLength(self) {
  if (typedArrayTag.call(self) === undefined) throw new TypeError('this is not a typed array');
  var length = typedArrayLength.call(self);
  if (length === 0) {
    // A detached buffer reads as empty; the specification throws for it.
    try {
      new Uint8Array(typedArrayBuffer.call(self));
    } catch (e) {
      throw new TypeError('the typed array is detached');
    }
  }
  return length;
}

fillIn(TypedArrayPrototype, 'at', function at(index) {
  var k = relativeIndex(index, validTypedArrayLength(this));
  return k < 0 ? undefined : this[k];
});

// FindViaPredicate from the end: the last element the predicate holds for,
// and its index, read from `object` as the search reaches it.
function findLastOf(object, length, predicate, thisArg) {
  if (typeof predicate !== 'function') throw new TypeError('the predicate is not a function');
  for (var k = length - 1; k >= 0; k--) {
    var value = object[k];
    if (predicate.call(thisArg, value, k, object)) return { index: k, value: value };
  }
  return { index: -1, value: undefined };
}

function arrayObject(self, name) {
  if (self === null || self === undefined) throw new TypeError('Array.prototype.' + name + ' called on null or undefined');
  return Object(self);
}

fillIn(Array.prototype, 'findLast', function findLast(predicate) {
  var object = arrayObject(this, 'findLast');
  return findLastOf(object, lengthOfArrayLike(object), predicate, arguments[1]).value;
});

fillIn(Array.prototype, 'findLastIndex', function findLastIndex(predicate) {
  var object = arrayObject(this, 'findLastIndex');
  return findLastOf(object, lengthOfArrayLike(object), predicate, arguments[1]).index;
});

fillIn(TypedArrayPrototype, 'findLast', function findLast(predicate) {
  return findLastOf(this, validTypedArrayLength(this), predicate, arguments[1]).value;
});

fillIn(TypedArrayPrototype, 'findLastIndex', function findLastIndex(predicate) {
  return findLastOf(this, validTypedArrayLength(this), predicate, arguments[1]).index;
});

if (typeof TextEncoder === 'undefined') define('TextEncoder', Encoder, false);
if (typeof TextDecoder === 'undefined') define('TextDecoder', Decoder, false);
if (typeof atob === 'undefined') define('atob', atob_, true);
if (typeof btoa === 'undefined') define('btoa', btoa_, true);
if (typeof URL === 'undefined') define('URL', Locator, false);
if (typeof URLSearchParams === 'undefined') define('URLSearchParams', Search, false);
if (typeof structuredClone === 'undefined') define('structuredClone', structuredClone_, true);
})(globalThis);
"""##
}
#endif
