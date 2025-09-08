// build/dev/javascript/prelude.mjs
var CustomType = class {
  withFields(fields) {
    let properties = Object.keys(this).map(
      (label2) => label2 in fields ? fields[label2] : this[label2]
    );
    return new this.constructor(...properties);
  }
};
var List = class {
  static fromArray(array3, tail) {
    let t = tail || new Empty();
    for (let i = array3.length - 1; i >= 0; --i) {
      t = new NonEmpty(array3[i], t);
    }
    return t;
  }
  [Symbol.iterator]() {
    return new ListIterator(this);
  }
  toArray() {
    return [...this];
  }
  // @internal
  atLeastLength(desired) {
    let current = this;
    while (desired-- > 0 && current) current = current.tail;
    return current !== void 0;
  }
  // @internal
  hasLength(desired) {
    let current = this;
    while (desired-- > 0 && current) current = current.tail;
    return desired === -1 && current instanceof Empty;
  }
  // @internal
  countLength() {
    let current = this;
    let length3 = 0;
    while (current) {
      current = current.tail;
      length3++;
    }
    return length3 - 1;
  }
};
function prepend(element4, tail) {
  return new NonEmpty(element4, tail);
}
function toList(elements, tail) {
  return List.fromArray(elements, tail);
}
var ListIterator = class {
  #current;
  constructor(current) {
    this.#current = current;
  }
  next() {
    if (this.#current instanceof Empty) {
      return { done: true };
    } else {
      let { head, tail } = this.#current;
      this.#current = tail;
      return { value: head, done: false };
    }
  }
};
var Empty = class extends List {
};
var NonEmpty = class extends List {
  constructor(head, tail) {
    super();
    this.head = head;
    this.tail = tail;
  }
};
var BitArray = class {
  /**
   * The size in bits of this bit array's data.
   *
   * @type {number}
   */
  bitSize;
  /**
   * The size in bytes of this bit array's data. If this bit array doesn't store
   * a whole number of bytes then this value is rounded up.
   *
   * @type {number}
   */
  byteSize;
  /**
   * The number of unused high bits in the first byte of this bit array's
   * buffer prior to the start of its data. The value of any unused high bits is
   * undefined.
   *
   * The bit offset will be in the range 0-7.
   *
   * @type {number}
   */
  bitOffset;
  /**
   * The raw bytes that hold this bit array's data.
   *
   * If `bitOffset` is not zero then there are unused high bits in the first
   * byte of this buffer.
   *
   * If `bitOffset + bitSize` is not a multiple of 8 then there are unused low
   * bits in the last byte of this buffer.
   *
   * @type {Uint8Array}
   */
  rawBuffer;
  /**
   * Constructs a new bit array from a `Uint8Array`, an optional size in
   * bits, and an optional bit offset.
   *
   * If no bit size is specified it is taken as `buffer.length * 8`, i.e. all
   * bytes in the buffer make up the new bit array's data.
   *
   * If no bit offset is specified it defaults to zero, i.e. there are no unused
   * high bits in the first byte of the buffer.
   *
   * @param {Uint8Array} buffer
   * @param {number} [bitSize]
   * @param {number} [bitOffset]
   */
  constructor(buffer, bitSize, bitOffset) {
    if (!(buffer instanceof Uint8Array)) {
      throw globalThis.Error(
        "BitArray can only be constructed from a Uint8Array"
      );
    }
    this.bitSize = bitSize ?? buffer.length * 8;
    this.byteSize = Math.trunc((this.bitSize + 7) / 8);
    this.bitOffset = bitOffset ?? 0;
    if (this.bitSize < 0) {
      throw globalThis.Error(`BitArray bit size is invalid: ${this.bitSize}`);
    }
    if (this.bitOffset < 0 || this.bitOffset > 7) {
      throw globalThis.Error(
        `BitArray bit offset is invalid: ${this.bitOffset}`
      );
    }
    if (buffer.length !== Math.trunc((this.bitOffset + this.bitSize + 7) / 8)) {
      throw globalThis.Error("BitArray buffer length is invalid");
    }
    this.rawBuffer = buffer;
  }
  /**
   * Returns a specific byte in this bit array. If the byte index is out of
   * range then `undefined` is returned.
   *
   * When returning the final byte of a bit array with a bit size that's not a
   * multiple of 8, the content of the unused low bits are undefined.
   *
   * @param {number} index
   * @returns {number | undefined}
   */
  byteAt(index4) {
    if (index4 < 0 || index4 >= this.byteSize) {
      return void 0;
    }
    return bitArrayByteAt(this.rawBuffer, this.bitOffset, index4);
  }
  /** @internal */
  equals(other) {
    if (this.bitSize !== other.bitSize) {
      return false;
    }
    const wholeByteCount = Math.trunc(this.bitSize / 8);
    if (this.bitOffset === 0 && other.bitOffset === 0) {
      for (let i = 0; i < wholeByteCount; i++) {
        if (this.rawBuffer[i] !== other.rawBuffer[i]) {
          return false;
        }
      }
      const trailingBitsCount = this.bitSize % 8;
      if (trailingBitsCount) {
        const unusedLowBitCount = 8 - trailingBitsCount;
        if (this.rawBuffer[wholeByteCount] >> unusedLowBitCount !== other.rawBuffer[wholeByteCount] >> unusedLowBitCount) {
          return false;
        }
      }
    } else {
      for (let i = 0; i < wholeByteCount; i++) {
        const a = bitArrayByteAt(this.rawBuffer, this.bitOffset, i);
        const b = bitArrayByteAt(other.rawBuffer, other.bitOffset, i);
        if (a !== b) {
          return false;
        }
      }
      const trailingBitsCount = this.bitSize % 8;
      if (trailingBitsCount) {
        const a = bitArrayByteAt(
          this.rawBuffer,
          this.bitOffset,
          wholeByteCount
        );
        const b = bitArrayByteAt(
          other.rawBuffer,
          other.bitOffset,
          wholeByteCount
        );
        const unusedLowBitCount = 8 - trailingBitsCount;
        if (a >> unusedLowBitCount !== b >> unusedLowBitCount) {
          return false;
        }
      }
    }
    return true;
  }
  /**
   * Returns this bit array's internal buffer.
   *
   * @deprecated Use `BitArray.byteAt()` or `BitArray.rawBuffer` instead.
   *
   * @returns {Uint8Array}
   */
  get buffer() {
    bitArrayPrintDeprecationWarning(
      "buffer",
      "Use BitArray.byteAt() or BitArray.rawBuffer instead"
    );
    if (this.bitOffset !== 0 || this.bitSize % 8 !== 0) {
      throw new globalThis.Error(
        "BitArray.buffer does not support unaligned bit arrays"
      );
    }
    return this.rawBuffer;
  }
  /**
   * Returns the length in bytes of this bit array's internal buffer.
   *
   * @deprecated Use `BitArray.bitSize` or `BitArray.byteSize` instead.
   *
   * @returns {number}
   */
  get length() {
    bitArrayPrintDeprecationWarning(
      "length",
      "Use BitArray.bitSize or BitArray.byteSize instead"
    );
    if (this.bitOffset !== 0 || this.bitSize % 8 !== 0) {
      throw new globalThis.Error(
        "BitArray.length does not support unaligned bit arrays"
      );
    }
    return this.rawBuffer.length;
  }
};
function bitArrayByteAt(buffer, bitOffset, index4) {
  if (bitOffset === 0) {
    return buffer[index4] ?? 0;
  } else {
    const a = buffer[index4] << bitOffset & 255;
    const b = buffer[index4 + 1] >> 8 - bitOffset;
    return a | b;
  }
}
var isBitArrayDeprecationMessagePrinted = {};
function bitArrayPrintDeprecationWarning(name2, message) {
  if (isBitArrayDeprecationMessagePrinted[name2]) {
    return;
  }
  console.warn(
    `Deprecated BitArray.${name2} property used in JavaScript FFI code. ${message}.`
  );
  isBitArrayDeprecationMessagePrinted[name2] = true;
}
var Result = class _Result extends CustomType {
  // @internal
  static isResult(data) {
    return data instanceof _Result;
  }
};
var Ok = class extends Result {
  constructor(value2) {
    super();
    this[0] = value2;
  }
  // @internal
  isOk() {
    return true;
  }
};
var Error = class extends Result {
  constructor(detail) {
    super();
    this[0] = detail;
  }
  // @internal
  isOk() {
    return false;
  }
};
function isEqual(x, y) {
  let values3 = [x, y];
  while (values3.length) {
    let a = values3.pop();
    let b = values3.pop();
    if (a === b) continue;
    if (!isObject(a) || !isObject(b)) return false;
    let unequal = !structurallyCompatibleObjects(a, b) || unequalDates(a, b) || unequalBuffers(a, b) || unequalArrays(a, b) || unequalMaps(a, b) || unequalSets(a, b) || unequalRegExps(a, b);
    if (unequal) return false;
    const proto = Object.getPrototypeOf(a);
    if (proto !== null && typeof proto.equals === "function") {
      try {
        if (a.equals(b)) continue;
        else return false;
      } catch {
      }
    }
    let [keys2, get2] = getters(a);
    const ka = keys2(a);
    const kb = keys2(b);
    if (ka.length !== kb.length) return false;
    for (let k of ka) {
      values3.push(get2(a, k), get2(b, k));
    }
  }
  return true;
}
function getters(object4) {
  if (object4 instanceof Map) {
    return [(x) => x.keys(), (x, y) => x.get(y)];
  } else {
    let extra = object4 instanceof globalThis.Error ? ["message"] : [];
    return [(x) => [...extra, ...Object.keys(x)], (x, y) => x[y]];
  }
}
function unequalDates(a, b) {
  return a instanceof Date && (a > b || a < b);
}
function unequalBuffers(a, b) {
  return !(a instanceof BitArray) && a.buffer instanceof ArrayBuffer && a.BYTES_PER_ELEMENT && !(a.byteLength === b.byteLength && a.every((n, i) => n === b[i]));
}
function unequalArrays(a, b) {
  return Array.isArray(a) && a.length !== b.length;
}
function unequalMaps(a, b) {
  return a instanceof Map && a.size !== b.size;
}
function unequalSets(a, b) {
  return a instanceof Set && (a.size != b.size || [...a].some((e) => !b.has(e)));
}
function unequalRegExps(a, b) {
  return a instanceof RegExp && (a.source !== b.source || a.flags !== b.flags);
}
function isObject(a) {
  return typeof a === "object" && a !== null;
}
function structurallyCompatibleObjects(a, b) {
  if (typeof a !== "object" && typeof b !== "object" && (!a || !b))
    return false;
  let nonstructural = [Promise, WeakSet, WeakMap, Function];
  if (nonstructural.some((c) => a instanceof c)) return false;
  return a.constructor === b.constructor;
}

// build/dev/javascript/gleam_stdlib/gleam/option.mjs
var Some = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var None = class extends CustomType {
};
function from_result(result) {
  if (result instanceof Ok) {
    let a = result[0];
    return new Some(a);
  } else {
    return new None();
  }
}
function unwrap(option2, default$) {
  if (option2 instanceof Some) {
    let x = option2[0];
    return x;
  } else {
    return default$;
  }
}

// build/dev/javascript/gleam_stdlib/dict.mjs
var referenceMap = /* @__PURE__ */ new WeakMap();
var tempDataView = /* @__PURE__ */ new DataView(
  /* @__PURE__ */ new ArrayBuffer(8)
);
var referenceUID = 0;
function hashByReference(o) {
  const known = referenceMap.get(o);
  if (known !== void 0) {
    return known;
  }
  const hash = referenceUID++;
  if (referenceUID === 2147483647) {
    referenceUID = 0;
  }
  referenceMap.set(o, hash);
  return hash;
}
function hashMerge(a, b) {
  return a ^ b + 2654435769 + (a << 6) + (a >> 2) | 0;
}
function hashString(s) {
  let hash = 0;
  const len = s.length;
  for (let i = 0; i < len; i++) {
    hash = Math.imul(31, hash) + s.charCodeAt(i) | 0;
  }
  return hash;
}
function hashNumber(n) {
  tempDataView.setFloat64(0, n);
  const i = tempDataView.getInt32(0);
  const j = tempDataView.getInt32(4);
  return Math.imul(73244475, i >> 16 ^ i) ^ j;
}
function hashBigInt(n) {
  return hashString(n.toString());
}
function hashObject(o) {
  const proto = Object.getPrototypeOf(o);
  if (proto !== null && typeof proto.hashCode === "function") {
    try {
      const code = o.hashCode(o);
      if (typeof code === "number") {
        return code;
      }
    } catch {
    }
  }
  if (o instanceof Promise || o instanceof WeakSet || o instanceof WeakMap) {
    return hashByReference(o);
  }
  if (o instanceof Date) {
    return hashNumber(o.getTime());
  }
  let h = 0;
  if (o instanceof ArrayBuffer) {
    o = new Uint8Array(o);
  }
  if (Array.isArray(o) || o instanceof Uint8Array) {
    for (let i = 0; i < o.length; i++) {
      h = Math.imul(31, h) + getHash(o[i]) | 0;
    }
  } else if (o instanceof Set) {
    o.forEach((v) => {
      h = h + getHash(v) | 0;
    });
  } else if (o instanceof Map) {
    o.forEach((v, k) => {
      h = h + hashMerge(getHash(v), getHash(k)) | 0;
    });
  } else {
    const keys2 = Object.keys(o);
    for (let i = 0; i < keys2.length; i++) {
      const k = keys2[i];
      const v = o[k];
      h = h + hashMerge(getHash(v), hashString(k)) | 0;
    }
  }
  return h;
}
function getHash(u) {
  if (u === null) return 1108378658;
  if (u === void 0) return 1108378659;
  if (u === true) return 1108378657;
  if (u === false) return 1108378656;
  switch (typeof u) {
    case "number":
      return hashNumber(u);
    case "string":
      return hashString(u);
    case "bigint":
      return hashBigInt(u);
    case "object":
      return hashObject(u);
    case "symbol":
      return hashByReference(u);
    case "function":
      return hashByReference(u);
    default:
      return 0;
  }
}
var SHIFT = 5;
var BUCKET_SIZE = Math.pow(2, SHIFT);
var MASK = BUCKET_SIZE - 1;
var MAX_INDEX_NODE = BUCKET_SIZE / 2;
var MIN_ARRAY_NODE = BUCKET_SIZE / 4;
var ENTRY = 0;
var ARRAY_NODE = 1;
var INDEX_NODE = 2;
var COLLISION_NODE = 3;
var EMPTY = {
  type: INDEX_NODE,
  bitmap: 0,
  array: []
};
function mask(hash, shift) {
  return hash >>> shift & MASK;
}
function bitpos(hash, shift) {
  return 1 << mask(hash, shift);
}
function bitcount(x) {
  x -= x >> 1 & 1431655765;
  x = (x & 858993459) + (x >> 2 & 858993459);
  x = x + (x >> 4) & 252645135;
  x += x >> 8;
  x += x >> 16;
  return x & 127;
}
function index(bitmap, bit) {
  return bitcount(bitmap & bit - 1);
}
function cloneAndSet(arr, at2, val) {
  const len = arr.length;
  const out = new Array(len);
  for (let i = 0; i < len; ++i) {
    out[i] = arr[i];
  }
  out[at2] = val;
  return out;
}
function spliceIn(arr, at2, val) {
  const len = arr.length;
  const out = new Array(len + 1);
  let i = 0;
  let g = 0;
  while (i < at2) {
    out[g++] = arr[i++];
  }
  out[g++] = val;
  while (i < len) {
    out[g++] = arr[i++];
  }
  return out;
}
function spliceOut(arr, at2) {
  const len = arr.length;
  const out = new Array(len - 1);
  let i = 0;
  let g = 0;
  while (i < at2) {
    out[g++] = arr[i++];
  }
  ++i;
  while (i < len) {
    out[g++] = arr[i++];
  }
  return out;
}
function createNode(shift, key1, val1, key2hash, key2, val2) {
  const key1hash = getHash(key1);
  if (key1hash === key2hash) {
    return {
      type: COLLISION_NODE,
      hash: key1hash,
      array: [
        { type: ENTRY, k: key1, v: val1 },
        { type: ENTRY, k: key2, v: val2 }
      ]
    };
  }
  const addedLeaf = { val: false };
  return assoc(
    assocIndex(EMPTY, shift, key1hash, key1, val1, addedLeaf),
    shift,
    key2hash,
    key2,
    val2,
    addedLeaf
  );
}
function assoc(root3, shift, hash, key, val, addedLeaf) {
  switch (root3.type) {
    case ARRAY_NODE:
      return assocArray(root3, shift, hash, key, val, addedLeaf);
    case INDEX_NODE:
      return assocIndex(root3, shift, hash, key, val, addedLeaf);
    case COLLISION_NODE:
      return assocCollision(root3, shift, hash, key, val, addedLeaf);
  }
}
function assocArray(root3, shift, hash, key, val, addedLeaf) {
  const idx = mask(hash, shift);
  const node = root3.array[idx];
  if (node === void 0) {
    addedLeaf.val = true;
    return {
      type: ARRAY_NODE,
      size: root3.size + 1,
      array: cloneAndSet(root3.array, idx, { type: ENTRY, k: key, v: val })
    };
  }
  if (node.type === ENTRY) {
    if (isEqual(key, node.k)) {
      if (val === node.v) {
        return root3;
      }
      return {
        type: ARRAY_NODE,
        size: root3.size,
        array: cloneAndSet(root3.array, idx, {
          type: ENTRY,
          k: key,
          v: val
        })
      };
    }
    addedLeaf.val = true;
    return {
      type: ARRAY_NODE,
      size: root3.size,
      array: cloneAndSet(
        root3.array,
        idx,
        createNode(shift + SHIFT, node.k, node.v, hash, key, val)
      )
    };
  }
  const n = assoc(node, shift + SHIFT, hash, key, val, addedLeaf);
  if (n === node) {
    return root3;
  }
  return {
    type: ARRAY_NODE,
    size: root3.size,
    array: cloneAndSet(root3.array, idx, n)
  };
}
function assocIndex(root3, shift, hash, key, val, addedLeaf) {
  const bit = bitpos(hash, shift);
  const idx = index(root3.bitmap, bit);
  if ((root3.bitmap & bit) !== 0) {
    const node = root3.array[idx];
    if (node.type !== ENTRY) {
      const n = assoc(node, shift + SHIFT, hash, key, val, addedLeaf);
      if (n === node) {
        return root3;
      }
      return {
        type: INDEX_NODE,
        bitmap: root3.bitmap,
        array: cloneAndSet(root3.array, idx, n)
      };
    }
    const nodeKey = node.k;
    if (isEqual(key, nodeKey)) {
      if (val === node.v) {
        return root3;
      }
      return {
        type: INDEX_NODE,
        bitmap: root3.bitmap,
        array: cloneAndSet(root3.array, idx, {
          type: ENTRY,
          k: key,
          v: val
        })
      };
    }
    addedLeaf.val = true;
    return {
      type: INDEX_NODE,
      bitmap: root3.bitmap,
      array: cloneAndSet(
        root3.array,
        idx,
        createNode(shift + SHIFT, nodeKey, node.v, hash, key, val)
      )
    };
  } else {
    const n = root3.array.length;
    if (n >= MAX_INDEX_NODE) {
      const nodes = new Array(32);
      const jdx = mask(hash, shift);
      nodes[jdx] = assocIndex(EMPTY, shift + SHIFT, hash, key, val, addedLeaf);
      let j = 0;
      let bitmap = root3.bitmap;
      for (let i = 0; i < 32; i++) {
        if ((bitmap & 1) !== 0) {
          const node = root3.array[j++];
          nodes[i] = node;
        }
        bitmap = bitmap >>> 1;
      }
      return {
        type: ARRAY_NODE,
        size: n + 1,
        array: nodes
      };
    } else {
      const newArray = spliceIn(root3.array, idx, {
        type: ENTRY,
        k: key,
        v: val
      });
      addedLeaf.val = true;
      return {
        type: INDEX_NODE,
        bitmap: root3.bitmap | bit,
        array: newArray
      };
    }
  }
}
function assocCollision(root3, shift, hash, key, val, addedLeaf) {
  if (hash === root3.hash) {
    const idx = collisionIndexOf(root3, key);
    if (idx !== -1) {
      const entry = root3.array[idx];
      if (entry.v === val) {
        return root3;
      }
      return {
        type: COLLISION_NODE,
        hash,
        array: cloneAndSet(root3.array, idx, { type: ENTRY, k: key, v: val })
      };
    }
    const size2 = root3.array.length;
    addedLeaf.val = true;
    return {
      type: COLLISION_NODE,
      hash,
      array: cloneAndSet(root3.array, size2, { type: ENTRY, k: key, v: val })
    };
  }
  return assoc(
    {
      type: INDEX_NODE,
      bitmap: bitpos(root3.hash, shift),
      array: [root3]
    },
    shift,
    hash,
    key,
    val,
    addedLeaf
  );
}
function collisionIndexOf(root3, key) {
  const size2 = root3.array.length;
  for (let i = 0; i < size2; i++) {
    if (isEqual(key, root3.array[i].k)) {
      return i;
    }
  }
  return -1;
}
function find(root3, shift, hash, key) {
  switch (root3.type) {
    case ARRAY_NODE:
      return findArray(root3, shift, hash, key);
    case INDEX_NODE:
      return findIndex(root3, shift, hash, key);
    case COLLISION_NODE:
      return findCollision(root3, key);
  }
}
function findArray(root3, shift, hash, key) {
  const idx = mask(hash, shift);
  const node = root3.array[idx];
  if (node === void 0) {
    return void 0;
  }
  if (node.type !== ENTRY) {
    return find(node, shift + SHIFT, hash, key);
  }
  if (isEqual(key, node.k)) {
    return node;
  }
  return void 0;
}
function findIndex(root3, shift, hash, key) {
  const bit = bitpos(hash, shift);
  if ((root3.bitmap & bit) === 0) {
    return void 0;
  }
  const idx = index(root3.bitmap, bit);
  const node = root3.array[idx];
  if (node.type !== ENTRY) {
    return find(node, shift + SHIFT, hash, key);
  }
  if (isEqual(key, node.k)) {
    return node;
  }
  return void 0;
}
function findCollision(root3, key) {
  const idx = collisionIndexOf(root3, key);
  if (idx < 0) {
    return void 0;
  }
  return root3.array[idx];
}
function without(root3, shift, hash, key) {
  switch (root3.type) {
    case ARRAY_NODE:
      return withoutArray(root3, shift, hash, key);
    case INDEX_NODE:
      return withoutIndex(root3, shift, hash, key);
    case COLLISION_NODE:
      return withoutCollision(root3, key);
  }
}
function withoutArray(root3, shift, hash, key) {
  const idx = mask(hash, shift);
  const node = root3.array[idx];
  if (node === void 0) {
    return root3;
  }
  let n = void 0;
  if (node.type === ENTRY) {
    if (!isEqual(node.k, key)) {
      return root3;
    }
  } else {
    n = without(node, shift + SHIFT, hash, key);
    if (n === node) {
      return root3;
    }
  }
  if (n === void 0) {
    if (root3.size <= MIN_ARRAY_NODE) {
      const arr = root3.array;
      const out = new Array(root3.size - 1);
      let i = 0;
      let j = 0;
      let bitmap = 0;
      while (i < idx) {
        const nv = arr[i];
        if (nv !== void 0) {
          out[j] = nv;
          bitmap |= 1 << i;
          ++j;
        }
        ++i;
      }
      ++i;
      while (i < arr.length) {
        const nv = arr[i];
        if (nv !== void 0) {
          out[j] = nv;
          bitmap |= 1 << i;
          ++j;
        }
        ++i;
      }
      return {
        type: INDEX_NODE,
        bitmap,
        array: out
      };
    }
    return {
      type: ARRAY_NODE,
      size: root3.size - 1,
      array: cloneAndSet(root3.array, idx, n)
    };
  }
  return {
    type: ARRAY_NODE,
    size: root3.size,
    array: cloneAndSet(root3.array, idx, n)
  };
}
function withoutIndex(root3, shift, hash, key) {
  const bit = bitpos(hash, shift);
  if ((root3.bitmap & bit) === 0) {
    return root3;
  }
  const idx = index(root3.bitmap, bit);
  const node = root3.array[idx];
  if (node.type !== ENTRY) {
    const n = without(node, shift + SHIFT, hash, key);
    if (n === node) {
      return root3;
    }
    if (n !== void 0) {
      return {
        type: INDEX_NODE,
        bitmap: root3.bitmap,
        array: cloneAndSet(root3.array, idx, n)
      };
    }
    if (root3.bitmap === bit) {
      return void 0;
    }
    return {
      type: INDEX_NODE,
      bitmap: root3.bitmap ^ bit,
      array: spliceOut(root3.array, idx)
    };
  }
  if (isEqual(key, node.k)) {
    if (root3.bitmap === bit) {
      return void 0;
    }
    return {
      type: INDEX_NODE,
      bitmap: root3.bitmap ^ bit,
      array: spliceOut(root3.array, idx)
    };
  }
  return root3;
}
function withoutCollision(root3, key) {
  const idx = collisionIndexOf(root3, key);
  if (idx < 0) {
    return root3;
  }
  if (root3.array.length === 1) {
    return void 0;
  }
  return {
    type: COLLISION_NODE,
    hash: root3.hash,
    array: spliceOut(root3.array, idx)
  };
}
function forEach(root3, fn) {
  if (root3 === void 0) {
    return;
  }
  const items = root3.array;
  const size2 = items.length;
  for (let i = 0; i < size2; i++) {
    const item = items[i];
    if (item === void 0) {
      continue;
    }
    if (item.type === ENTRY) {
      fn(item.v, item.k);
      continue;
    }
    forEach(item, fn);
  }
}
var Dict = class _Dict {
  /**
   * @template V
   * @param {Record<string,V>} o
   * @returns {Dict<string,V>}
   */
  static fromObject(o) {
    const keys2 = Object.keys(o);
    let m = _Dict.new();
    for (let i = 0; i < keys2.length; i++) {
      const k = keys2[i];
      m = m.set(k, o[k]);
    }
    return m;
  }
  /**
   * @template K,V
   * @param {Map<K,V>} o
   * @returns {Dict<K,V>}
   */
  static fromMap(o) {
    let m = _Dict.new();
    o.forEach((v, k) => {
      m = m.set(k, v);
    });
    return m;
  }
  static new() {
    return new _Dict(void 0, 0);
  }
  /**
   * @param {undefined | Node<K,V>} root
   * @param {number} size
   */
  constructor(root3, size2) {
    this.root = root3;
    this.size = size2;
  }
  /**
   * @template NotFound
   * @param {K} key
   * @param {NotFound} notFound
   * @returns {NotFound | V}
   */
  get(key, notFound) {
    if (this.root === void 0) {
      return notFound;
    }
    const found = find(this.root, 0, getHash(key), key);
    if (found === void 0) {
      return notFound;
    }
    return found.v;
  }
  /**
   * @param {K} key
   * @param {V} val
   * @returns {Dict<K,V>}
   */
  set(key, val) {
    const addedLeaf = { val: false };
    const root3 = this.root === void 0 ? EMPTY : this.root;
    const newRoot = assoc(root3, 0, getHash(key), key, val, addedLeaf);
    if (newRoot === this.root) {
      return this;
    }
    return new _Dict(newRoot, addedLeaf.val ? this.size + 1 : this.size);
  }
  /**
   * @param {K} key
   * @returns {Dict<K,V>}
   */
  delete(key) {
    if (this.root === void 0) {
      return this;
    }
    const newRoot = without(this.root, 0, getHash(key), key);
    if (newRoot === this.root) {
      return this;
    }
    if (newRoot === void 0) {
      return _Dict.new();
    }
    return new _Dict(newRoot, this.size - 1);
  }
  /**
   * @param {K} key
   * @returns {boolean}
   */
  has(key) {
    if (this.root === void 0) {
      return false;
    }
    return find(this.root, 0, getHash(key), key) !== void 0;
  }
  /**
   * @returns {[K,V][]}
   */
  entries() {
    if (this.root === void 0) {
      return [];
    }
    const result = [];
    this.forEach((v, k) => result.push([k, v]));
    return result;
  }
  /**
   *
   * @param {(val:V,key:K)=>void} fn
   */
  forEach(fn) {
    forEach(this.root, fn);
  }
  hashCode() {
    let h = 0;
    this.forEach((v, k) => {
      h = h + hashMerge(getHash(v), getHash(k)) | 0;
    });
    return h;
  }
  /**
   * @param {unknown} o
   * @returns {boolean}
   */
  equals(o) {
    if (!(o instanceof _Dict) || this.size !== o.size) {
      return false;
    }
    try {
      this.forEach((v, k) => {
        if (!isEqual(o.get(k, !v), v)) {
          throw unequalDictSymbol;
        }
      });
      return true;
    } catch (e) {
      if (e === unequalDictSymbol) {
        return false;
      }
      throw e;
    }
  }
};
var unequalDictSymbol = /* @__PURE__ */ Symbol();

// build/dev/javascript/gleam_stdlib/gleam/dict.mjs
function insert(dict4, key, value2) {
  return map_insert(key, value2, dict4);
}
function reverse_and_concat(loop$remaining, loop$accumulator) {
  while (true) {
    let remaining = loop$remaining;
    let accumulator = loop$accumulator;
    if (remaining instanceof Empty) {
      return accumulator;
    } else {
      let first = remaining.head;
      let rest = remaining.tail;
      loop$remaining = rest;
      loop$accumulator = prepend(first, accumulator);
    }
  }
}
function do_keys_loop(loop$list, loop$acc) {
  while (true) {
    let list4 = loop$list;
    let acc = loop$acc;
    if (list4 instanceof Empty) {
      return reverse_and_concat(acc, toList([]));
    } else {
      let rest = list4.tail;
      let key = list4.head[0];
      loop$list = rest;
      loop$acc = prepend(key, acc);
    }
  }
}
function keys(dict4) {
  return do_keys_loop(map_to_list(dict4), toList([]));
}
function delete$(dict4, key) {
  return map_remove(key, dict4);
}
function fold_loop(loop$list, loop$initial, loop$fun) {
  while (true) {
    let list4 = loop$list;
    let initial = loop$initial;
    let fun = loop$fun;
    if (list4 instanceof Empty) {
      return initial;
    } else {
      let rest = list4.tail;
      let k = list4.head[0];
      let v = list4.head[1];
      loop$list = rest;
      loop$initial = fun(initial, k, v);
      loop$fun = fun;
    }
  }
}
function fold(dict4, initial, fun) {
  return fold_loop(map_to_list(dict4), initial, fun);
}

// build/dev/javascript/gleam_stdlib/gleam/order.mjs
var Lt = class extends CustomType {
};
var Eq = class extends CustomType {
};
var Gt = class extends CustomType {
};

// build/dev/javascript/gleam_stdlib/gleam/list.mjs
var Ascending = class extends CustomType {
};
var Descending = class extends CustomType {
};
function length_loop(loop$list, loop$count) {
  while (true) {
    let list4 = loop$list;
    let count = loop$count;
    if (list4 instanceof Empty) {
      return count;
    } else {
      let list$1 = list4.tail;
      loop$list = list$1;
      loop$count = count + 1;
    }
  }
}
function length(list4) {
  return length_loop(list4, 0);
}
function reverse_and_prepend(loop$prefix, loop$suffix) {
  while (true) {
    let prefix = loop$prefix;
    let suffix = loop$suffix;
    if (prefix instanceof Empty) {
      return suffix;
    } else {
      let first$1 = prefix.head;
      let rest$1 = prefix.tail;
      loop$prefix = rest$1;
      loop$suffix = prepend(first$1, suffix);
    }
  }
}
function reverse(list4) {
  return reverse_and_prepend(list4, toList([]));
}
function contains(loop$list, loop$elem) {
  while (true) {
    let list4 = loop$list;
    let elem = loop$elem;
    if (list4 instanceof Empty) {
      return false;
    } else {
      let first$1 = list4.head;
      if (isEqual(first$1, elem)) {
        return true;
      } else {
        let rest$1 = list4.tail;
        loop$list = rest$1;
        loop$elem = elem;
      }
    }
  }
}
function filter_map_loop(loop$list, loop$fun, loop$acc) {
  while (true) {
    let list4 = loop$list;
    let fun = loop$fun;
    let acc = loop$acc;
    if (list4 instanceof Empty) {
      return reverse(acc);
    } else {
      let first$1 = list4.head;
      let rest$1 = list4.tail;
      let _block;
      let $ = fun(first$1);
      if ($ instanceof Ok) {
        let first$2 = $[0];
        _block = prepend(first$2, acc);
      } else {
        _block = acc;
      }
      let new_acc = _block;
      loop$list = rest$1;
      loop$fun = fun;
      loop$acc = new_acc;
    }
  }
}
function filter_map(list4, fun) {
  return filter_map_loop(list4, fun, toList([]));
}
function map_loop(loop$list, loop$fun, loop$acc) {
  while (true) {
    let list4 = loop$list;
    let fun = loop$fun;
    let acc = loop$acc;
    if (list4 instanceof Empty) {
      return reverse(acc);
    } else {
      let first$1 = list4.head;
      let rest$1 = list4.tail;
      loop$list = rest$1;
      loop$fun = fun;
      loop$acc = prepend(fun(first$1), acc);
    }
  }
}
function map(list4, fun) {
  return map_loop(list4, fun, toList([]));
}
function index_map_loop(loop$list, loop$fun, loop$index, loop$acc) {
  while (true) {
    let list4 = loop$list;
    let fun = loop$fun;
    let index4 = loop$index;
    let acc = loop$acc;
    if (list4 instanceof Empty) {
      return reverse(acc);
    } else {
      let first$1 = list4.head;
      let rest$1 = list4.tail;
      let acc$1 = prepend(fun(first$1, index4), acc);
      loop$list = rest$1;
      loop$fun = fun;
      loop$index = index4 + 1;
      loop$acc = acc$1;
    }
  }
}
function index_map(list4, fun) {
  return index_map_loop(list4, fun, 0, toList([]));
}
function append_loop(loop$first, loop$second) {
  while (true) {
    let first = loop$first;
    let second = loop$second;
    if (first instanceof Empty) {
      return second;
    } else {
      let first$1 = first.head;
      let rest$1 = first.tail;
      loop$first = rest$1;
      loop$second = prepend(first$1, second);
    }
  }
}
function append(first, second) {
  return append_loop(reverse(first), second);
}
function flatten_loop(loop$lists, loop$acc) {
  while (true) {
    let lists = loop$lists;
    let acc = loop$acc;
    if (lists instanceof Empty) {
      return reverse(acc);
    } else {
      let list4 = lists.head;
      let further_lists = lists.tail;
      loop$lists = further_lists;
      loop$acc = reverse_and_prepend(list4, acc);
    }
  }
}
function flatten(lists) {
  return flatten_loop(lists, toList([]));
}
function fold2(loop$list, loop$initial, loop$fun) {
  while (true) {
    let list4 = loop$list;
    let initial = loop$initial;
    let fun = loop$fun;
    if (list4 instanceof Empty) {
      return initial;
    } else {
      let first$1 = list4.head;
      let rest$1 = list4.tail;
      loop$list = rest$1;
      loop$initial = fun(initial, first$1);
      loop$fun = fun;
    }
  }
}
function index_fold_loop(loop$over, loop$acc, loop$with, loop$index) {
  while (true) {
    let over = loop$over;
    let acc = loop$acc;
    let with$ = loop$with;
    let index4 = loop$index;
    if (over instanceof Empty) {
      return acc;
    } else {
      let first$1 = over.head;
      let rest$1 = over.tail;
      loop$over = rest$1;
      loop$acc = with$(acc, first$1, index4);
      loop$with = with$;
      loop$index = index4 + 1;
    }
  }
}
function index_fold(list4, initial, fun) {
  return index_fold_loop(list4, initial, fun, 0);
}
function find2(loop$list, loop$is_desired) {
  while (true) {
    let list4 = loop$list;
    let is_desired = loop$is_desired;
    if (list4 instanceof Empty) {
      return new Error(void 0);
    } else {
      let first$1 = list4.head;
      let rest$1 = list4.tail;
      let $ = is_desired(first$1);
      if ($) {
        return new Ok(first$1);
      } else {
        loop$list = rest$1;
        loop$is_desired = is_desired;
      }
    }
  }
}
function sequences(loop$list, loop$compare, loop$growing, loop$direction, loop$prev, loop$acc) {
  while (true) {
    let list4 = loop$list;
    let compare4 = loop$compare;
    let growing = loop$growing;
    let direction = loop$direction;
    let prev = loop$prev;
    let acc = loop$acc;
    let growing$1 = prepend(prev, growing);
    if (list4 instanceof Empty) {
      if (direction instanceof Ascending) {
        return prepend(reverse(growing$1), acc);
      } else {
        return prepend(growing$1, acc);
      }
    } else {
      let new$1 = list4.head;
      let rest$1 = list4.tail;
      let $ = compare4(prev, new$1);
      if (direction instanceof Ascending) {
        if ($ instanceof Lt) {
          loop$list = rest$1;
          loop$compare = compare4;
          loop$growing = growing$1;
          loop$direction = direction;
          loop$prev = new$1;
          loop$acc = acc;
        } else if ($ instanceof Eq) {
          loop$list = rest$1;
          loop$compare = compare4;
          loop$growing = growing$1;
          loop$direction = direction;
          loop$prev = new$1;
          loop$acc = acc;
        } else {
          let _block;
          if (direction instanceof Ascending) {
            _block = prepend(reverse(growing$1), acc);
          } else {
            _block = prepend(growing$1, acc);
          }
          let acc$1 = _block;
          if (rest$1 instanceof Empty) {
            return prepend(toList([new$1]), acc$1);
          } else {
            let next = rest$1.head;
            let rest$2 = rest$1.tail;
            let _block$1;
            let $1 = compare4(new$1, next);
            if ($1 instanceof Lt) {
              _block$1 = new Ascending();
            } else if ($1 instanceof Eq) {
              _block$1 = new Ascending();
            } else {
              _block$1 = new Descending();
            }
            let direction$1 = _block$1;
            loop$list = rest$2;
            loop$compare = compare4;
            loop$growing = toList([new$1]);
            loop$direction = direction$1;
            loop$prev = next;
            loop$acc = acc$1;
          }
        }
      } else if ($ instanceof Lt) {
        let _block;
        if (direction instanceof Ascending) {
          _block = prepend(reverse(growing$1), acc);
        } else {
          _block = prepend(growing$1, acc);
        }
        let acc$1 = _block;
        if (rest$1 instanceof Empty) {
          return prepend(toList([new$1]), acc$1);
        } else {
          let next = rest$1.head;
          let rest$2 = rest$1.tail;
          let _block$1;
          let $1 = compare4(new$1, next);
          if ($1 instanceof Lt) {
            _block$1 = new Ascending();
          } else if ($1 instanceof Eq) {
            _block$1 = new Ascending();
          } else {
            _block$1 = new Descending();
          }
          let direction$1 = _block$1;
          loop$list = rest$2;
          loop$compare = compare4;
          loop$growing = toList([new$1]);
          loop$direction = direction$1;
          loop$prev = next;
          loop$acc = acc$1;
        }
      } else if ($ instanceof Eq) {
        let _block;
        if (direction instanceof Ascending) {
          _block = prepend(reverse(growing$1), acc);
        } else {
          _block = prepend(growing$1, acc);
        }
        let acc$1 = _block;
        if (rest$1 instanceof Empty) {
          return prepend(toList([new$1]), acc$1);
        } else {
          let next = rest$1.head;
          let rest$2 = rest$1.tail;
          let _block$1;
          let $1 = compare4(new$1, next);
          if ($1 instanceof Lt) {
            _block$1 = new Ascending();
          } else if ($1 instanceof Eq) {
            _block$1 = new Ascending();
          } else {
            _block$1 = new Descending();
          }
          let direction$1 = _block$1;
          loop$list = rest$2;
          loop$compare = compare4;
          loop$growing = toList([new$1]);
          loop$direction = direction$1;
          loop$prev = next;
          loop$acc = acc$1;
        }
      } else {
        loop$list = rest$1;
        loop$compare = compare4;
        loop$growing = growing$1;
        loop$direction = direction;
        loop$prev = new$1;
        loop$acc = acc;
      }
    }
  }
}
function merge_ascendings(loop$list1, loop$list2, loop$compare, loop$acc) {
  while (true) {
    let list1 = loop$list1;
    let list22 = loop$list2;
    let compare4 = loop$compare;
    let acc = loop$acc;
    if (list1 instanceof Empty) {
      let list4 = list22;
      return reverse_and_prepend(list4, acc);
    } else if (list22 instanceof Empty) {
      let list4 = list1;
      return reverse_and_prepend(list4, acc);
    } else {
      let first1 = list1.head;
      let rest1 = list1.tail;
      let first2 = list22.head;
      let rest2 = list22.tail;
      let $ = compare4(first1, first2);
      if ($ instanceof Lt) {
        loop$list1 = rest1;
        loop$list2 = list22;
        loop$compare = compare4;
        loop$acc = prepend(first1, acc);
      } else if ($ instanceof Eq) {
        loop$list1 = list1;
        loop$list2 = rest2;
        loop$compare = compare4;
        loop$acc = prepend(first2, acc);
      } else {
        loop$list1 = list1;
        loop$list2 = rest2;
        loop$compare = compare4;
        loop$acc = prepend(first2, acc);
      }
    }
  }
}
function merge_ascending_pairs(loop$sequences, loop$compare, loop$acc) {
  while (true) {
    let sequences2 = loop$sequences;
    let compare4 = loop$compare;
    let acc = loop$acc;
    if (sequences2 instanceof Empty) {
      return reverse(acc);
    } else {
      let $ = sequences2.tail;
      if ($ instanceof Empty) {
        let sequence = sequences2.head;
        return reverse(prepend(reverse(sequence), acc));
      } else {
        let ascending1 = sequences2.head;
        let ascending2 = $.head;
        let rest$1 = $.tail;
        let descending = merge_ascendings(
          ascending1,
          ascending2,
          compare4,
          toList([])
        );
        loop$sequences = rest$1;
        loop$compare = compare4;
        loop$acc = prepend(descending, acc);
      }
    }
  }
}
function merge_descendings(loop$list1, loop$list2, loop$compare, loop$acc) {
  while (true) {
    let list1 = loop$list1;
    let list22 = loop$list2;
    let compare4 = loop$compare;
    let acc = loop$acc;
    if (list1 instanceof Empty) {
      let list4 = list22;
      return reverse_and_prepend(list4, acc);
    } else if (list22 instanceof Empty) {
      let list4 = list1;
      return reverse_and_prepend(list4, acc);
    } else {
      let first1 = list1.head;
      let rest1 = list1.tail;
      let first2 = list22.head;
      let rest2 = list22.tail;
      let $ = compare4(first1, first2);
      if ($ instanceof Lt) {
        loop$list1 = list1;
        loop$list2 = rest2;
        loop$compare = compare4;
        loop$acc = prepend(first2, acc);
      } else if ($ instanceof Eq) {
        loop$list1 = rest1;
        loop$list2 = list22;
        loop$compare = compare4;
        loop$acc = prepend(first1, acc);
      } else {
        loop$list1 = rest1;
        loop$list2 = list22;
        loop$compare = compare4;
        loop$acc = prepend(first1, acc);
      }
    }
  }
}
function merge_descending_pairs(loop$sequences, loop$compare, loop$acc) {
  while (true) {
    let sequences2 = loop$sequences;
    let compare4 = loop$compare;
    let acc = loop$acc;
    if (sequences2 instanceof Empty) {
      return reverse(acc);
    } else {
      let $ = sequences2.tail;
      if ($ instanceof Empty) {
        let sequence = sequences2.head;
        return reverse(prepend(reverse(sequence), acc));
      } else {
        let descending1 = sequences2.head;
        let descending2 = $.head;
        let rest$1 = $.tail;
        let ascending = merge_descendings(
          descending1,
          descending2,
          compare4,
          toList([])
        );
        loop$sequences = rest$1;
        loop$compare = compare4;
        loop$acc = prepend(ascending, acc);
      }
    }
  }
}
function merge_all(loop$sequences, loop$direction, loop$compare) {
  while (true) {
    let sequences2 = loop$sequences;
    let direction = loop$direction;
    let compare4 = loop$compare;
    if (sequences2 instanceof Empty) {
      return sequences2;
    } else if (direction instanceof Ascending) {
      let $ = sequences2.tail;
      if ($ instanceof Empty) {
        let sequence = sequences2.head;
        return sequence;
      } else {
        let sequences$1 = merge_ascending_pairs(sequences2, compare4, toList([]));
        loop$sequences = sequences$1;
        loop$direction = new Descending();
        loop$compare = compare4;
      }
    } else {
      let $ = sequences2.tail;
      if ($ instanceof Empty) {
        let sequence = sequences2.head;
        return reverse(sequence);
      } else {
        let sequences$1 = merge_descending_pairs(sequences2, compare4, toList([]));
        loop$sequences = sequences$1;
        loop$direction = new Ascending();
        loop$compare = compare4;
      }
    }
  }
}
function sort(list4, compare4) {
  if (list4 instanceof Empty) {
    return list4;
  } else {
    let $ = list4.tail;
    if ($ instanceof Empty) {
      return list4;
    } else {
      let x = list4.head;
      let y = $.head;
      let rest$1 = $.tail;
      let _block;
      let $1 = compare4(x, y);
      if ($1 instanceof Lt) {
        _block = new Ascending();
      } else if ($1 instanceof Eq) {
        _block = new Ascending();
      } else {
        _block = new Descending();
      }
      let direction = _block;
      let sequences$1 = sequences(
        rest$1,
        compare4,
        toList([x]),
        direction,
        y,
        toList([])
      );
      return merge_all(sequences$1, new Ascending(), compare4);
    }
  }
}
function repeat_loop(loop$item, loop$times, loop$acc) {
  while (true) {
    let item = loop$item;
    let times = loop$times;
    let acc = loop$acc;
    let $ = times <= 0;
    if ($) {
      return acc;
    } else {
      loop$item = item;
      loop$times = times - 1;
      loop$acc = prepend(item, acc);
    }
  }
}
function repeat(a, times) {
  return repeat_loop(a, times, toList([]));
}
function last(loop$list) {
  while (true) {
    let list4 = loop$list;
    if (list4 instanceof Empty) {
      return new Error(void 0);
    } else {
      let $ = list4.tail;
      if ($ instanceof Empty) {
        let last$1 = list4.head;
        return new Ok(last$1);
      } else {
        let rest$1 = $;
        loop$list = rest$1;
      }
    }
  }
}

// build/dev/javascript/gleam_stdlib/gleam/string.mjs
function replace(string5, pattern, substitute) {
  let _pipe = string5;
  let _pipe$1 = identity(_pipe);
  let _pipe$2 = string_replace(_pipe$1, pattern, substitute);
  return identity(_pipe$2);
}
function append2(first, second) {
  return first + second;
}
function concat_loop(loop$strings, loop$accumulator) {
  while (true) {
    let strings = loop$strings;
    let accumulator = loop$accumulator;
    if (strings instanceof Empty) {
      return accumulator;
    } else {
      let string5 = strings.head;
      let strings$1 = strings.tail;
      loop$strings = strings$1;
      loop$accumulator = accumulator + string5;
    }
  }
}
function concat2(strings) {
  return concat_loop(strings, "");
}
function join_loop(loop$strings, loop$separator, loop$accumulator) {
  while (true) {
    let strings = loop$strings;
    let separator = loop$separator;
    let accumulator = loop$accumulator;
    if (strings instanceof Empty) {
      return accumulator;
    } else {
      let string5 = strings.head;
      let strings$1 = strings.tail;
      loop$strings = strings$1;
      loop$separator = separator;
      loop$accumulator = accumulator + separator + string5;
    }
  }
}
function join(strings, separator) {
  if (strings instanceof Empty) {
    return "";
  } else {
    let first$1 = strings.head;
    let rest = strings.tail;
    return join_loop(rest, separator, first$1);
  }
}
function capitalise(string5) {
  let $ = pop_grapheme(string5);
  if ($ instanceof Ok) {
    let first$1 = $[0][0];
    let rest = $[0][1];
    return append2(uppercase(first$1), lowercase(rest));
  } else {
    return "";
  }
}

// build/dev/javascript/gleam_stdlib/gleam/dynamic/decode.mjs
var DecodeError = class extends CustomType {
  constructor(expected, found, path) {
    super();
    this.expected = expected;
    this.found = found;
    this.path = path;
  }
};
var Decoder = class extends CustomType {
  constructor(function$) {
    super();
    this.function = function$;
  }
};
function run(data, decoder) {
  let $ = decoder.function(data);
  let maybe_invalid_data;
  let errors;
  maybe_invalid_data = $[0];
  errors = $[1];
  if (errors instanceof Empty) {
    return new Ok(maybe_invalid_data);
  } else {
    return new Error(errors);
  }
}
function success(data) {
  return new Decoder((_) => {
    return [data, toList([])];
  });
}
function decode_dynamic(data) {
  return [data, toList([])];
}
function map2(decoder, transformer) {
  return new Decoder(
    (d) => {
      let $ = decoder.function(d);
      let data;
      let errors;
      data = $[0];
      errors = $[1];
      return [transformer(data), errors];
    }
  );
}
function then$(decoder, next) {
  return new Decoder(
    (dynamic_data) => {
      let $ = decoder.function(dynamic_data);
      let data;
      let errors;
      data = $[0];
      errors = $[1];
      let decoder$1 = next(data);
      let $1 = decoder$1.function(dynamic_data);
      let layer;
      let data$1;
      layer = $1;
      data$1 = $1[0];
      if (errors instanceof Empty) {
        return layer;
      } else {
        return [data$1, errors];
      }
    }
  );
}
function run_decoders(loop$data, loop$failure, loop$decoders) {
  while (true) {
    let data = loop$data;
    let failure2 = loop$failure;
    let decoders = loop$decoders;
    if (decoders instanceof Empty) {
      return failure2;
    } else {
      let decoder = decoders.head;
      let decoders$1 = decoders.tail;
      let $ = decoder.function(data);
      let layer;
      let errors;
      layer = $;
      errors = $[1];
      if (errors instanceof Empty) {
        return layer;
      } else {
        loop$data = data;
        loop$failure = failure2;
        loop$decoders = decoders$1;
      }
    }
  }
}
function one_of(first, alternatives) {
  return new Decoder(
    (dynamic_data) => {
      let $ = first.function(dynamic_data);
      let layer;
      let errors;
      layer = $;
      errors = $[1];
      if (errors instanceof Empty) {
        return layer;
      } else {
        return run_decoders(dynamic_data, layer, alternatives);
      }
    }
  );
}
function optional(inner) {
  return new Decoder(
    (data) => {
      let $ = is_null(data);
      if ($) {
        return [new None(), toList([])];
      } else {
        let $1 = inner.function(data);
        let data$1;
        let errors;
        data$1 = $1[0];
        errors = $1[1];
        return [new Some(data$1), errors];
      }
    }
  );
}
var dynamic = /* @__PURE__ */ new Decoder(decode_dynamic);
function decode_error(expected, found) {
  return toList([
    new DecodeError(expected, classify_dynamic(found), toList([]))
  ]);
}
function run_dynamic_function(data, name2, f) {
  let $ = f(data);
  if ($ instanceof Ok) {
    let data$1 = $[0];
    return [data$1, toList([])];
  } else {
    let zero = $[0];
    return [
      zero,
      toList([new DecodeError(name2, classify_dynamic(data), toList([]))])
    ];
  }
}
function decode_bool(data) {
  let $ = isEqual(identity(true), data);
  if ($) {
    return [true, toList([])];
  } else {
    let $1 = isEqual(identity(false), data);
    if ($1) {
      return [false, toList([])];
    } else {
      return [false, decode_error("Bool", data)];
    }
  }
}
function decode_int(data) {
  return run_dynamic_function(data, "Int", int);
}
function decode_float(data) {
  return run_dynamic_function(data, "Float", float);
}
function failure(zero, expected) {
  return new Decoder((d) => {
    return [zero, decode_error(expected, d)];
  });
}
var bool = /* @__PURE__ */ new Decoder(decode_bool);
var int2 = /* @__PURE__ */ new Decoder(decode_int);
var float2 = /* @__PURE__ */ new Decoder(decode_float);
function decode_string(data) {
  return run_dynamic_function(data, "String", string);
}
var string2 = /* @__PURE__ */ new Decoder(decode_string);
function fold_dict(acc, key, value2, key_decoder, value_decoder) {
  let $ = key_decoder(key);
  let $1 = $[1];
  if ($1 instanceof Empty) {
    let key$1 = $[0];
    let $2 = value_decoder(value2);
    let $3 = $2[1];
    if ($3 instanceof Empty) {
      let value$1 = $2[0];
      let dict$1 = insert(acc[0], key$1, value$1);
      return [dict$1, acc[1]];
    } else {
      let errors = $3;
      return push_path([new_map(), errors], toList(["values"]));
    }
  } else {
    let errors = $1;
    return push_path([new_map(), errors], toList(["keys"]));
  }
}
function dict2(key, value2) {
  return new Decoder(
    (data) => {
      let $ = dict(data);
      if ($ instanceof Ok) {
        let dict$1 = $[0];
        return fold(
          dict$1,
          [new_map(), toList([])],
          (a, k, v) => {
            let $1 = a[1];
            if ($1 instanceof Empty) {
              return fold_dict(a, k, v, key.function, value2.function);
            } else {
              return a;
            }
          }
        );
      } else {
        return [new_map(), decode_error("Dict", data)];
      }
    }
  );
}
function list2(inner) {
  return new Decoder(
    (data) => {
      return list(
        data,
        inner.function,
        (p2, k) => {
          return push_path(p2, toList([k]));
        },
        0,
        toList([])
      );
    }
  );
}
function push_path(layer, path) {
  let decoder = one_of(
    string2,
    toList([
      (() => {
        let _pipe = int2;
        return map2(_pipe, to_string);
      })()
    ])
  );
  let path$1 = map(
    path,
    (key) => {
      let key$1 = identity(key);
      let $ = run(key$1, decoder);
      if ($ instanceof Ok) {
        let key$2 = $[0];
        return key$2;
      } else {
        return "<" + classify_dynamic(key$1) + ">";
      }
    }
  );
  let errors = map(
    layer[1],
    (error) => {
      return new DecodeError(
        error.expected,
        error.found,
        append(path$1, error.path)
      );
    }
  );
  return [layer[0], errors];
}
function index3(loop$path, loop$position, loop$inner, loop$data, loop$handle_miss) {
  while (true) {
    let path = loop$path;
    let position = loop$position;
    let inner = loop$inner;
    let data = loop$data;
    let handle_miss = loop$handle_miss;
    if (path instanceof Empty) {
      let _pipe = inner(data);
      return push_path(_pipe, reverse(position));
    } else {
      let key = path.head;
      let path$1 = path.tail;
      let $ = index2(data, key);
      if ($ instanceof Ok) {
        let $1 = $[0];
        if ($1 instanceof Some) {
          let data$1 = $1[0];
          loop$path = path$1;
          loop$position = prepend(key, position);
          loop$inner = inner;
          loop$data = data$1;
          loop$handle_miss = handle_miss;
        } else {
          return handle_miss(data, prepend(key, position));
        }
      } else {
        let kind = $[0];
        let $1 = inner(data);
        let default$;
        default$ = $1[0];
        let _pipe = [
          default$,
          toList([new DecodeError(kind, classify_dynamic(data), toList([]))])
        ];
        return push_path(_pipe, reverse(position));
      }
    }
  }
}
function subfield(field_path, field_decoder, next) {
  return new Decoder(
    (data) => {
      let $ = index3(
        field_path,
        toList([]),
        field_decoder.function,
        data,
        (data2, position) => {
          let $12 = field_decoder.function(data2);
          let default$;
          default$ = $12[0];
          let _pipe = [
            default$,
            toList([new DecodeError("Field", "Nothing", toList([]))])
          ];
          return push_path(_pipe, reverse(position));
        }
      );
      let out;
      let errors1;
      out = $[0];
      errors1 = $[1];
      let $1 = next(out).function(data);
      let out$1;
      let errors2;
      out$1 = $1[0];
      errors2 = $1[1];
      return [out$1, append(errors1, errors2)];
    }
  );
}
function at(path, inner) {
  return new Decoder(
    (data) => {
      return index3(
        path,
        toList([]),
        inner.function,
        data,
        (data2, position) => {
          let $ = inner.function(data2);
          let default$;
          default$ = $[0];
          let _pipe = [
            default$,
            toList([new DecodeError("Field", "Nothing", toList([]))])
          ];
          return push_path(_pipe, reverse(position));
        }
      );
    }
  );
}
function field(field_name, field_decoder, next) {
  return subfield(toList([field_name]), field_decoder, next);
}
function optional_field(key, default$, field_decoder, next) {
  return new Decoder(
    (data) => {
      let _block;
      let _block$1;
      let $1 = index2(data, key);
      if ($1 instanceof Ok) {
        let $22 = $1[0];
        if ($22 instanceof Some) {
          let data$1 = $22[0];
          _block$1 = field_decoder.function(data$1);
        } else {
          _block$1 = [default$, toList([])];
        }
      } else {
        let kind = $1[0];
        _block$1 = [
          default$,
          toList([new DecodeError(kind, classify_dynamic(data), toList([]))])
        ];
      }
      let _pipe = _block$1;
      _block = push_path(_pipe, toList([key]));
      let $ = _block;
      let out;
      let errors1;
      out = $[0];
      errors1 = $[1];
      let $2 = next(out).function(data);
      let out$1;
      let errors2;
      out$1 = $2[0];
      errors2 = $2[1];
      return [out$1, append(errors1, errors2)];
    }
  );
}

// build/dev/javascript/gleam_stdlib/gleam_stdlib.mjs
var Nil = void 0;
var NOT_FOUND = {};
function identity(x) {
  return x;
}
function parse_int(value2) {
  if (/^[-+]?(\d+)$/.test(value2)) {
    return new Ok(parseInt(value2));
  } else {
    return new Error(Nil);
  }
}
function parse_float(value2) {
  if (/^[-+]?(\d+)\.(\d+)([eE][-+]?\d+)?$/.test(value2)) {
    return new Ok(parseFloat(value2));
  } else {
    return new Error(Nil);
  }
}
function to_string(term) {
  return term.toString();
}
function string_replace(string5, target, substitute) {
  return string5.replaceAll(target, substitute);
}
function string_length(string5) {
  if (string5 === "") {
    return 0;
  }
  const iterator = graphemes_iterator(string5);
  if (iterator) {
    let i = 0;
    for (const _ of iterator) {
      i++;
    }
    return i;
  } else {
    return string5.match(/./gsu).length;
  }
}
var segmenter = void 0;
function graphemes_iterator(string5) {
  if (globalThis.Intl && Intl.Segmenter) {
    segmenter ||= new Intl.Segmenter();
    return segmenter.segment(string5)[Symbol.iterator]();
  }
}
function pop_grapheme(string5) {
  let first;
  const iterator = graphemes_iterator(string5);
  if (iterator) {
    first = iterator.next().value?.segment;
  } else {
    first = string5.match(/./su)?.[0];
  }
  if (first) {
    return new Ok([first, string5.slice(first.length)]);
  } else {
    return new Error(Nil);
  }
}
function lowercase(string5) {
  return string5.toLowerCase();
}
function uppercase(string5) {
  return string5.toUpperCase();
}
function contains_string(haystack, needle) {
  return haystack.indexOf(needle) >= 0;
}
function starts_with(haystack, needle) {
  return haystack.startsWith(needle);
}
var unicode_whitespaces = [
  " ",
  // Space
  "	",
  // Horizontal tab
  "\n",
  // Line feed
  "\v",
  // Vertical tab
  "\f",
  // Form feed
  "\r",
  // Carriage return
  "\x85",
  // Next line
  "\u2028",
  // Line separator
  "\u2029"
  // Paragraph separator
].join("");
var trim_start_regex = /* @__PURE__ */ new RegExp(
  `^[${unicode_whitespaces}]*`
);
var trim_end_regex = /* @__PURE__ */ new RegExp(`[${unicode_whitespaces}]*$`);
function console_log(term) {
  console.log(term);
}
function new_map() {
  return Dict.new();
}
function map_size(map4) {
  return map4.size;
}
function map_to_list(map4) {
  return List.fromArray(map4.entries());
}
function map_remove(key, map4) {
  return map4.delete(key);
}
function map_get(map4, key) {
  const value2 = map4.get(key, NOT_FOUND);
  if (value2 === NOT_FOUND) {
    return new Error(Nil);
  }
  return new Ok(value2);
}
function map_insert(key, value2, map4) {
  return map4.set(key, value2);
}
function classify_dynamic(data) {
  if (typeof data === "string") {
    return "String";
  } else if (typeof data === "boolean") {
    return "Bool";
  } else if (data instanceof Result) {
    return "Result";
  } else if (data instanceof List) {
    return "List";
  } else if (data instanceof BitArray) {
    return "BitArray";
  } else if (data instanceof Dict) {
    return "Dict";
  } else if (Number.isInteger(data)) {
    return "Int";
  } else if (Array.isArray(data)) {
    return `Array`;
  } else if (typeof data === "number") {
    return "Float";
  } else if (data === null) {
    return "Nil";
  } else if (data === void 0) {
    return "Nil";
  } else {
    const type = typeof data;
    return type.charAt(0).toUpperCase() + type.slice(1);
  }
}
function float_to_string(float3) {
  const string5 = float3.toString().replace("+", "");
  if (string5.indexOf(".") >= 0) {
    return string5;
  } else {
    const index4 = string5.indexOf("e");
    if (index4 >= 0) {
      return string5.slice(0, index4) + ".0" + string5.slice(index4);
    } else {
      return string5 + ".0";
    }
  }
}
function index2(data, key) {
  if (data instanceof Dict || data instanceof WeakMap || data instanceof Map) {
    const token = {};
    const entry = data.get(key, token);
    if (entry === token) return new Ok(new None());
    return new Ok(new Some(entry));
  }
  const key_is_int = Number.isInteger(key);
  if (key_is_int && key >= 0 && key < 8 && data instanceof List) {
    let i = 0;
    for (const value2 of data) {
      if (i === key) return new Ok(new Some(value2));
      i++;
    }
    return new Error("Indexable");
  }
  if (key_is_int && Array.isArray(data) || data && typeof data === "object" || data && Object.getPrototypeOf(data) === Object.prototype) {
    if (key in data) return new Ok(new Some(data[key]));
    return new Ok(new None());
  }
  return new Error(key_is_int ? "Indexable" : "Dict");
}
function list(data, decode2, pushPath, index4, emptyList) {
  if (!(data instanceof List || Array.isArray(data))) {
    const error = new DecodeError("List", classify_dynamic(data), emptyList);
    return [emptyList, List.fromArray([error])];
  }
  const decoded = [];
  for (const element4 of data) {
    const layer = decode2(element4);
    const [out, errors] = layer;
    if (errors instanceof NonEmpty) {
      const [_, errors2] = pushPath(layer, index4.toString());
      return [emptyList, errors2];
    }
    decoded.push(out);
    index4++;
  }
  return [List.fromArray(decoded), emptyList];
}
function dict(data) {
  if (data instanceof Dict) {
    return new Ok(data);
  }
  if (data instanceof Map || data instanceof WeakMap) {
    return new Ok(Dict.fromMap(data));
  }
  if (data == null) {
    return new Error("Dict");
  }
  if (typeof data !== "object") {
    return new Error("Dict");
  }
  const proto = Object.getPrototypeOf(data);
  if (proto === Object.prototype || proto === null) {
    return new Ok(Dict.fromObject(data));
  }
  return new Error("Dict");
}
function float(data) {
  if (typeof data === "number") return new Ok(data);
  return new Error(0);
}
function int(data) {
  if (Number.isInteger(data)) return new Ok(data);
  return new Error(0);
}
function string(data) {
  if (typeof data === "string") return new Ok(data);
  return new Error("");
}
function is_null(data) {
  return data === null || data === void 0;
}

// build/dev/javascript/gleam_stdlib/gleam/result.mjs
function map3(result, fun) {
  if (result instanceof Ok) {
    let x = result[0];
    return new Ok(fun(x));
  } else {
    return result;
  }
}
function map_error(result, fun) {
  if (result instanceof Ok) {
    return result;
  } else {
    let error = result[0];
    return new Error(fun(error));
  }
}
function try$(result, fun) {
  if (result instanceof Ok) {
    let x = result[0];
    return fun(x);
  } else {
    return result;
  }
}
function unwrap2(result, default$) {
  if (result instanceof Ok) {
    let v = result[0];
    return v;
  } else {
    return default$;
  }
}
function values2(results) {
  return filter_map(results, (result) => {
    return result;
  });
}

// build/dev/javascript/gleam_stdlib/gleam/bool.mjs
function guard(requirement, consequence, alternative) {
  if (requirement) {
    return consequence;
  } else {
    return alternative();
  }
}

// build/dev/javascript/gleam_stdlib/gleam/function.mjs
function identity2(x) {
  return x;
}

// build/dev/javascript/gleam_json/gleam_json_ffi.mjs
function identity3(x) {
  return x;
}
function decode(string5) {
  try {
    const result = JSON.parse(string5);
    return new Ok(result);
  } catch (err) {
    return new Error(getJsonDecodeError(err, string5));
  }
}
function getJsonDecodeError(stdErr, json2) {
  if (isUnexpectedEndOfInput(stdErr)) return new UnexpectedEndOfInput();
  return toUnexpectedByteError(stdErr, json2);
}
function isUnexpectedEndOfInput(err) {
  const unexpectedEndOfInputRegex = /((unexpected (end|eof))|(end of data)|(unterminated string)|(json( parse error|\.parse)\: expected '(\:|\}|\])'))/i;
  return unexpectedEndOfInputRegex.test(err.message);
}
function toUnexpectedByteError(err, json2) {
  let converters = [
    v8UnexpectedByteError,
    oldV8UnexpectedByteError,
    jsCoreUnexpectedByteError,
    spidermonkeyUnexpectedByteError
  ];
  for (let converter of converters) {
    let result = converter(err, json2);
    if (result) return result;
  }
  return new UnexpectedByte("", 0);
}
function v8UnexpectedByteError(err) {
  const regex = /unexpected token '(.)', ".+" is not valid JSON/i;
  const match = regex.exec(err.message);
  if (!match) return null;
  const byte = toHex(match[1]);
  return new UnexpectedByte(byte, -1);
}
function oldV8UnexpectedByteError(err) {
  const regex = /unexpected token (.) in JSON at position (\d+)/i;
  const match = regex.exec(err.message);
  if (!match) return null;
  const byte = toHex(match[1]);
  const position = Number(match[2]);
  return new UnexpectedByte(byte, position);
}
function spidermonkeyUnexpectedByteError(err, json2) {
  const regex = /(unexpected character|expected .*) at line (\d+) column (\d+)/i;
  const match = regex.exec(err.message);
  if (!match) return null;
  const line = Number(match[2]);
  const column = Number(match[3]);
  const position = getPositionFromMultiline(line, column, json2);
  const byte = toHex(json2[position]);
  return new UnexpectedByte(byte, position);
}
function jsCoreUnexpectedByteError(err) {
  const regex = /unexpected (identifier|token) "(.)"/i;
  const match = regex.exec(err.message);
  if (!match) return null;
  const byte = toHex(match[2]);
  return new UnexpectedByte(byte, 0);
}
function toHex(char) {
  return "0x" + char.charCodeAt(0).toString(16).toUpperCase();
}
function getPositionFromMultiline(line, column, string5) {
  if (line === 1) return column - 1;
  let currentLn = 1;
  let position = 0;
  string5.split("").find((char, idx) => {
    if (char === "\n") currentLn += 1;
    if (currentLn === line) {
      position = idx + column;
      return true;
    }
    return false;
  });
  return position;
}

// build/dev/javascript/gleam_json/gleam/json.mjs
var UnexpectedEndOfInput = class extends CustomType {
};
var UnexpectedByte = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var UnexpectedSequence = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var UnableToDecode = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
function do_parse(json2, decoder) {
  return try$(
    decode(json2),
    (dynamic_value) => {
      let _pipe = run(dynamic_value, decoder);
      return map_error(
        _pipe,
        (var0) => {
          return new UnableToDecode(var0);
        }
      );
    }
  );
}
function parse(json2, decoder) {
  return do_parse(json2, decoder);
}
function string3(input2) {
  return identity3(input2);
}
function bool2(input2) {
  return identity3(input2);
}

// build/dev/javascript/lustre/lustre/internals/constants.ffi.mjs
var document = () => globalThis?.document;
var NAMESPACE_HTML = "http://www.w3.org/1999/xhtml";
var ELEMENT_NODE = 1;
var TEXT_NODE = 3;
var SUPPORTS_MOVE_BEFORE = !!globalThis.HTMLElement?.prototype?.moveBefore;

// build/dev/javascript/lustre/lustre/internals/constants.mjs
var empty_list = /* @__PURE__ */ toList([]);
var option_none = /* @__PURE__ */ new None();

// build/dev/javascript/lustre/lustre/vdom/vattr.ffi.mjs
var GT = /* @__PURE__ */ new Gt();
var LT = /* @__PURE__ */ new Lt();
var EQ = /* @__PURE__ */ new Eq();
function compare3(a, b) {
  if (a.name === b.name) {
    return EQ;
  } else if (a.name < b.name) {
    return LT;
  } else {
    return GT;
  }
}

// build/dev/javascript/lustre/lustre/vdom/vattr.mjs
var Attribute = class extends CustomType {
  constructor(kind, name2, value2) {
    super();
    this.kind = kind;
    this.name = name2;
    this.value = value2;
  }
};
var Property = class extends CustomType {
  constructor(kind, name2, value2) {
    super();
    this.kind = kind;
    this.name = name2;
    this.value = value2;
  }
};
var Event2 = class extends CustomType {
  constructor(kind, name2, handler, include, prevent_default2, stop_propagation, immediate, debounce, throttle) {
    super();
    this.kind = kind;
    this.name = name2;
    this.handler = handler;
    this.include = include;
    this.prevent_default = prevent_default2;
    this.stop_propagation = stop_propagation;
    this.immediate = immediate;
    this.debounce = debounce;
    this.throttle = throttle;
  }
};
var Handler = class extends CustomType {
  constructor(prevent_default2, stop_propagation, message) {
    super();
    this.prevent_default = prevent_default2;
    this.stop_propagation = stop_propagation;
    this.message = message;
  }
};
var Never = class extends CustomType {
  constructor(kind) {
    super();
    this.kind = kind;
  }
};
var Always = class extends CustomType {
  constructor(kind) {
    super();
    this.kind = kind;
  }
};
function merge(loop$attributes, loop$merged) {
  while (true) {
    let attributes = loop$attributes;
    let merged = loop$merged;
    if (attributes instanceof Empty) {
      return merged;
    } else {
      let $ = attributes.head;
      if ($ instanceof Attribute) {
        let $1 = $.name;
        if ($1 === "") {
          let rest = attributes.tail;
          loop$attributes = rest;
          loop$merged = merged;
        } else if ($1 === "class") {
          let $2 = $.value;
          if ($2 === "") {
            let rest = attributes.tail;
            loop$attributes = rest;
            loop$merged = merged;
          } else {
            let $3 = attributes.tail;
            if ($3 instanceof Empty) {
              let attribute$1 = $;
              let rest = $3;
              loop$attributes = rest;
              loop$merged = prepend(attribute$1, merged);
            } else {
              let $4 = $3.head;
              if ($4 instanceof Attribute) {
                let $5 = $4.name;
                if ($5 === "class") {
                  let kind = $.kind;
                  let class1 = $2;
                  let rest = $3.tail;
                  let class2 = $4.value;
                  let value2 = class1 + " " + class2;
                  let attribute$1 = new Attribute(kind, "class", value2);
                  loop$attributes = prepend(attribute$1, rest);
                  loop$merged = merged;
                } else {
                  let attribute$1 = $;
                  let rest = $3;
                  loop$attributes = rest;
                  loop$merged = prepend(attribute$1, merged);
                }
              } else {
                let attribute$1 = $;
                let rest = $3;
                loop$attributes = rest;
                loop$merged = prepend(attribute$1, merged);
              }
            }
          }
        } else if ($1 === "style") {
          let $2 = $.value;
          if ($2 === "") {
            let rest = attributes.tail;
            loop$attributes = rest;
            loop$merged = merged;
          } else {
            let $3 = attributes.tail;
            if ($3 instanceof Empty) {
              let attribute$1 = $;
              let rest = $3;
              loop$attributes = rest;
              loop$merged = prepend(attribute$1, merged);
            } else {
              let $4 = $3.head;
              if ($4 instanceof Attribute) {
                let $5 = $4.name;
                if ($5 === "style") {
                  let kind = $.kind;
                  let style1 = $2;
                  let rest = $3.tail;
                  let style2 = $4.value;
                  let value2 = style1 + ";" + style2;
                  let attribute$1 = new Attribute(kind, "style", value2);
                  loop$attributes = prepend(attribute$1, rest);
                  loop$merged = merged;
                } else {
                  let attribute$1 = $;
                  let rest = $3;
                  loop$attributes = rest;
                  loop$merged = prepend(attribute$1, merged);
                }
              } else {
                let attribute$1 = $;
                let rest = $3;
                loop$attributes = rest;
                loop$merged = prepend(attribute$1, merged);
              }
            }
          }
        } else {
          let attribute$1 = $;
          let rest = attributes.tail;
          loop$attributes = rest;
          loop$merged = prepend(attribute$1, merged);
        }
      } else {
        let attribute$1 = $;
        let rest = attributes.tail;
        loop$attributes = rest;
        loop$merged = prepend(attribute$1, merged);
      }
    }
  }
}
function prepare(attributes) {
  if (attributes instanceof Empty) {
    return attributes;
  } else {
    let $ = attributes.tail;
    if ($ instanceof Empty) {
      return attributes;
    } else {
      let _pipe = attributes;
      let _pipe$1 = sort(_pipe, (a, b) => {
        return compare3(b, a);
      });
      return merge(_pipe$1, empty_list);
    }
  }
}
var attribute_kind = 0;
function attribute(name2, value2) {
  return new Attribute(attribute_kind, name2, value2);
}
var property_kind = 1;
function property(name2, value2) {
  return new Property(property_kind, name2, value2);
}
var event_kind = 2;
function event(name2, handler, include, prevent_default2, stop_propagation, immediate, debounce, throttle) {
  return new Event2(
    event_kind,
    name2,
    handler,
    include,
    prevent_default2,
    stop_propagation,
    immediate,
    debounce,
    throttle
  );
}
var never_kind = 0;
var never = /* @__PURE__ */ new Never(never_kind);
var always_kind = 2;
var always = /* @__PURE__ */ new Always(always_kind);

// build/dev/javascript/lustre/lustre/attribute.mjs
function attribute2(name2, value2) {
  return attribute(name2, value2);
}
function property2(name2, value2) {
  return property(name2, value2);
}
function boolean_attribute(name2, value2) {
  if (value2) {
    return attribute2(name2, "");
  } else {
    return property2(name2, bool2(false));
  }
}
function class$(name2) {
  return attribute2("class", name2);
}
function id(value2) {
  return attribute2("id", value2);
}
function checked(is_checked) {
  return boolean_attribute("checked", is_checked);
}
function disabled(is_disabled) {
  return boolean_attribute("disabled", is_disabled);
}
function for$(id2) {
  return attribute2("for", id2);
}
function max2(value2) {
  return attribute2("max", value2);
}
function min2(value2) {
  return attribute2("min", value2);
}
function name(element_name) {
  return attribute2("name", element_name);
}
function required(is_required) {
  return boolean_attribute("required", is_required);
}
function selected(is_selected) {
  return boolean_attribute("selected", is_selected);
}
function step(value2) {
  return attribute2("step", value2);
}
function type_(control_type) {
  return attribute2("type", control_type);
}
function value(control_value) {
  return attribute2("value", control_value);
}

// build/dev/javascript/lustre/lustre/effect.mjs
var Effect = class extends CustomType {
  constructor(synchronous, before_paint2, after_paint) {
    super();
    this.synchronous = synchronous;
    this.before_paint = before_paint2;
    this.after_paint = after_paint;
  }
};
var empty = /* @__PURE__ */ new Effect(
  /* @__PURE__ */ toList([]),
  /* @__PURE__ */ toList([]),
  /* @__PURE__ */ toList([])
);
function none() {
  return empty;
}
function from(effect) {
  let task = (actions) => {
    let dispatch = actions.dispatch;
    return effect(dispatch);
  };
  return new Effect(toList([task]), empty.before_paint, empty.after_paint);
}

// build/dev/javascript/lustre/lustre/internals/mutable_map.ffi.mjs
function empty2() {
  return null;
}
function get(map4, key) {
  const value2 = map4?.get(key);
  if (value2 != null) {
    return new Ok(value2);
  } else {
    return new Error(void 0);
  }
}
function has_key2(map4, key) {
  return map4 && map4.has(key);
}
function insert2(map4, key, value2) {
  map4 ??= /* @__PURE__ */ new Map();
  map4.set(key, value2);
  return map4;
}
function remove(map4, key) {
  map4?.delete(key);
  return map4;
}

// build/dev/javascript/lustre/lustre/vdom/path.mjs
var Root = class extends CustomType {
};
var Key = class extends CustomType {
  constructor(key, parent) {
    super();
    this.key = key;
    this.parent = parent;
  }
};
var Index = class extends CustomType {
  constructor(index4, parent) {
    super();
    this.index = index4;
    this.parent = parent;
  }
};
function do_matches(loop$path, loop$candidates) {
  while (true) {
    let path = loop$path;
    let candidates = loop$candidates;
    if (candidates instanceof Empty) {
      return false;
    } else {
      let candidate = candidates.head;
      let rest = candidates.tail;
      let $ = starts_with(path, candidate);
      if ($) {
        return $;
      } else {
        loop$path = path;
        loop$candidates = rest;
      }
    }
  }
}
function add2(parent, index4, key) {
  if (key === "") {
    return new Index(index4, parent);
  } else {
    return new Key(key, parent);
  }
}
var root2 = /* @__PURE__ */ new Root();
var separator_element = "	";
function do_to_string(loop$path, loop$acc) {
  while (true) {
    let path = loop$path;
    let acc = loop$acc;
    if (path instanceof Root) {
      if (acc instanceof Empty) {
        return "";
      } else {
        let segments = acc.tail;
        return concat2(segments);
      }
    } else if (path instanceof Key) {
      let key = path.key;
      let parent = path.parent;
      loop$path = parent;
      loop$acc = prepend(separator_element, prepend(key, acc));
    } else {
      let index4 = path.index;
      let parent = path.parent;
      loop$path = parent;
      loop$acc = prepend(
        separator_element,
        prepend(to_string(index4), acc)
      );
    }
  }
}
function to_string2(path) {
  return do_to_string(path, toList([]));
}
function matches(path, candidates) {
  if (candidates instanceof Empty) {
    return false;
  } else {
    return do_matches(to_string2(path), candidates);
  }
}
var separator_event = "\n";
function event2(path, event4) {
  return do_to_string(path, toList([separator_event, event4]));
}

// build/dev/javascript/lustre/lustre/vdom/vnode.mjs
var Fragment = class extends CustomType {
  constructor(kind, key, mapper, children, keyed_children) {
    super();
    this.kind = kind;
    this.key = key;
    this.mapper = mapper;
    this.children = children;
    this.keyed_children = keyed_children;
  }
};
var Element = class extends CustomType {
  constructor(kind, key, mapper, namespace, tag, attributes, children, keyed_children, self_closing, void$) {
    super();
    this.kind = kind;
    this.key = key;
    this.mapper = mapper;
    this.namespace = namespace;
    this.tag = tag;
    this.attributes = attributes;
    this.children = children;
    this.keyed_children = keyed_children;
    this.self_closing = self_closing;
    this.void = void$;
  }
};
var Text = class extends CustomType {
  constructor(kind, key, mapper, content) {
    super();
    this.kind = kind;
    this.key = key;
    this.mapper = mapper;
    this.content = content;
  }
};
var UnsafeInnerHtml = class extends CustomType {
  constructor(kind, key, mapper, namespace, tag, attributes, inner_html) {
    super();
    this.kind = kind;
    this.key = key;
    this.mapper = mapper;
    this.namespace = namespace;
    this.tag = tag;
    this.attributes = attributes;
    this.inner_html = inner_html;
  }
};
function is_void_element(tag, namespace) {
  if (namespace === "") {
    if (tag === "area") {
      return true;
    } else if (tag === "base") {
      return true;
    } else if (tag === "br") {
      return true;
    } else if (tag === "col") {
      return true;
    } else if (tag === "embed") {
      return true;
    } else if (tag === "hr") {
      return true;
    } else if (tag === "img") {
      return true;
    } else if (tag === "input") {
      return true;
    } else if (tag === "link") {
      return true;
    } else if (tag === "meta") {
      return true;
    } else if (tag === "param") {
      return true;
    } else if (tag === "source") {
      return true;
    } else if (tag === "track") {
      return true;
    } else if (tag === "wbr") {
      return true;
    } else {
      return false;
    }
  } else {
    return false;
  }
}
function to_keyed(key, node) {
  if (node instanceof Fragment) {
    return new Fragment(
      node.kind,
      key,
      node.mapper,
      node.children,
      node.keyed_children
    );
  } else if (node instanceof Element) {
    return new Element(
      node.kind,
      key,
      node.mapper,
      node.namespace,
      node.tag,
      node.attributes,
      node.children,
      node.keyed_children,
      node.self_closing,
      node.void
    );
  } else if (node instanceof Text) {
    return new Text(node.kind, key, node.mapper, node.content);
  } else {
    return new UnsafeInnerHtml(
      node.kind,
      key,
      node.mapper,
      node.namespace,
      node.tag,
      node.attributes,
      node.inner_html
    );
  }
}
var fragment_kind = 0;
function fragment(key, mapper, children, keyed_children) {
  return new Fragment(fragment_kind, key, mapper, children, keyed_children);
}
var element_kind = 1;
function element(key, mapper, namespace, tag, attributes, children, keyed_children, self_closing, void$) {
  return new Element(
    element_kind,
    key,
    mapper,
    namespace,
    tag,
    prepare(attributes),
    children,
    keyed_children,
    self_closing,
    void$ || is_void_element(tag, namespace)
  );
}
var text_kind = 2;
function text(key, mapper, content) {
  return new Text(text_kind, key, mapper, content);
}
var unsafe_inner_html_kind = 3;

// build/dev/javascript/lustre/lustre/internals/equals.ffi.mjs
var isReferenceEqual = (a, b) => a === b;
var isEqual2 = (a, b) => {
  if (a === b) {
    return true;
  }
  if (a == null || b == null) {
    return false;
  }
  const type = typeof a;
  if (type !== typeof b) {
    return false;
  }
  if (type !== "object") {
    return false;
  }
  const ctor = a.constructor;
  if (ctor !== b.constructor) {
    return false;
  }
  if (Array.isArray(a)) {
    return areArraysEqual(a, b);
  }
  return areObjectsEqual(a, b);
};
var areArraysEqual = (a, b) => {
  let index4 = a.length;
  if (index4 !== b.length) {
    return false;
  }
  while (index4--) {
    if (!isEqual2(a[index4], b[index4])) {
      return false;
    }
  }
  return true;
};
var areObjectsEqual = (a, b) => {
  const properties = Object.keys(a);
  let index4 = properties.length;
  if (Object.keys(b).length !== index4) {
    return false;
  }
  while (index4--) {
    const property3 = properties[index4];
    if (!Object.hasOwn(b, property3)) {
      return false;
    }
    if (!isEqual2(a[property3], b[property3])) {
      return false;
    }
  }
  return true;
};

// build/dev/javascript/lustre/lustre/vdom/events.mjs
var Events = class extends CustomType {
  constructor(handlers, dispatched_paths, next_dispatched_paths) {
    super();
    this.handlers = handlers;
    this.dispatched_paths = dispatched_paths;
    this.next_dispatched_paths = next_dispatched_paths;
  }
};
function new$3() {
  return new Events(
    empty2(),
    empty_list,
    empty_list
  );
}
function tick(events) {
  return new Events(
    events.handlers,
    events.next_dispatched_paths,
    empty_list
  );
}
function do_remove_event(handlers, path, name2) {
  return remove(handlers, event2(path, name2));
}
function remove_event(events, path, name2) {
  let handlers = do_remove_event(events.handlers, path, name2);
  return new Events(
    handlers,
    events.dispatched_paths,
    events.next_dispatched_paths
  );
}
function remove_attributes(handlers, path, attributes) {
  return fold2(
    attributes,
    handlers,
    (events, attribute3) => {
      if (attribute3 instanceof Event2) {
        let name2 = attribute3.name;
        return do_remove_event(events, path, name2);
      } else {
        return events;
      }
    }
  );
}
function handle(events, path, name2, event4) {
  let next_dispatched_paths = prepend(path, events.next_dispatched_paths);
  let events$1 = new Events(
    events.handlers,
    events.dispatched_paths,
    next_dispatched_paths
  );
  let $ = get(
    events$1.handlers,
    path + separator_event + name2
  );
  if ($ instanceof Ok) {
    let handler = $[0];
    return [events$1, run(event4, handler)];
  } else {
    return [events$1, new Error(toList([]))];
  }
}
function has_dispatched_events(events, path) {
  return matches(path, events.dispatched_paths);
}
function do_add_event(handlers, mapper, path, name2, handler) {
  return insert2(
    handlers,
    event2(path, name2),
    map2(
      handler,
      (handler2) => {
        return new Handler(
          handler2.prevent_default,
          handler2.stop_propagation,
          identity2(mapper)(handler2.message)
        );
      }
    )
  );
}
function add_event(events, mapper, path, name2, handler) {
  let handlers = do_add_event(events.handlers, mapper, path, name2, handler);
  return new Events(
    handlers,
    events.dispatched_paths,
    events.next_dispatched_paths
  );
}
function add_attributes(handlers, mapper, path, attributes) {
  return fold2(
    attributes,
    handlers,
    (events, attribute3) => {
      if (attribute3 instanceof Event2) {
        let name2 = attribute3.name;
        let handler = attribute3.handler;
        return do_add_event(events, mapper, path, name2, handler);
      } else {
        return events;
      }
    }
  );
}
function compose_mapper(mapper, child_mapper) {
  let $ = isReferenceEqual(mapper, identity2);
  let $1 = isReferenceEqual(child_mapper, identity2);
  if ($1) {
    return mapper;
  } else if ($) {
    return child_mapper;
  } else {
    return (msg) => {
      return mapper(child_mapper(msg));
    };
  }
}
function do_remove_children(loop$handlers, loop$path, loop$child_index, loop$children) {
  while (true) {
    let handlers = loop$handlers;
    let path = loop$path;
    let child_index = loop$child_index;
    let children = loop$children;
    if (children instanceof Empty) {
      return handlers;
    } else {
      let child = children.head;
      let rest = children.tail;
      let _pipe = handlers;
      let _pipe$1 = do_remove_child(_pipe, path, child_index, child);
      loop$handlers = _pipe$1;
      loop$path = path;
      loop$child_index = child_index + 1;
      loop$children = rest;
    }
  }
}
function do_remove_child(handlers, parent, child_index, child) {
  if (child instanceof Fragment) {
    let children = child.children;
    let path = add2(parent, child_index, child.key);
    return do_remove_children(handlers, path, 0, children);
  } else if (child instanceof Element) {
    let attributes = child.attributes;
    let children = child.children;
    let path = add2(parent, child_index, child.key);
    let _pipe = handlers;
    let _pipe$1 = remove_attributes(_pipe, path, attributes);
    return do_remove_children(_pipe$1, path, 0, children);
  } else if (child instanceof Text) {
    return handlers;
  } else {
    let attributes = child.attributes;
    let path = add2(parent, child_index, child.key);
    return remove_attributes(handlers, path, attributes);
  }
}
function remove_child(events, parent, child_index, child) {
  let handlers = do_remove_child(events.handlers, parent, child_index, child);
  return new Events(
    handlers,
    events.dispatched_paths,
    events.next_dispatched_paths
  );
}
function do_add_children(loop$handlers, loop$mapper, loop$path, loop$child_index, loop$children) {
  while (true) {
    let handlers = loop$handlers;
    let mapper = loop$mapper;
    let path = loop$path;
    let child_index = loop$child_index;
    let children = loop$children;
    if (children instanceof Empty) {
      return handlers;
    } else {
      let child = children.head;
      let rest = children.tail;
      let _pipe = handlers;
      let _pipe$1 = do_add_child(_pipe, mapper, path, child_index, child);
      loop$handlers = _pipe$1;
      loop$mapper = mapper;
      loop$path = path;
      loop$child_index = child_index + 1;
      loop$children = rest;
    }
  }
}
function do_add_child(handlers, mapper, parent, child_index, child) {
  if (child instanceof Fragment) {
    let children = child.children;
    let path = add2(parent, child_index, child.key);
    let composed_mapper = compose_mapper(mapper, child.mapper);
    return do_add_children(handlers, composed_mapper, path, 0, children);
  } else if (child instanceof Element) {
    let attributes = child.attributes;
    let children = child.children;
    let path = add2(parent, child_index, child.key);
    let composed_mapper = compose_mapper(mapper, child.mapper);
    let _pipe = handlers;
    let _pipe$1 = add_attributes(_pipe, composed_mapper, path, attributes);
    return do_add_children(_pipe$1, composed_mapper, path, 0, children);
  } else if (child instanceof Text) {
    return handlers;
  } else {
    let attributes = child.attributes;
    let path = add2(parent, child_index, child.key);
    let composed_mapper = compose_mapper(mapper, child.mapper);
    return add_attributes(handlers, composed_mapper, path, attributes);
  }
}
function add_child(events, mapper, parent, index4, child) {
  let handlers = do_add_child(events.handlers, mapper, parent, index4, child);
  return new Events(
    handlers,
    events.dispatched_paths,
    events.next_dispatched_paths
  );
}
function add_children(events, mapper, path, child_index, children) {
  let handlers = do_add_children(
    events.handlers,
    mapper,
    path,
    child_index,
    children
  );
  return new Events(
    handlers,
    events.dispatched_paths,
    events.next_dispatched_paths
  );
}

// build/dev/javascript/lustre/lustre/element.mjs
function element2(tag, attributes, children) {
  return element(
    "",
    identity2,
    "",
    tag,
    attributes,
    children,
    empty2(),
    false,
    false
  );
}
function text2(content) {
  return text("", identity2, content);
}
function none2() {
  return text("", identity2, "");
}

// build/dev/javascript/lustre/lustre/element/html.mjs
function text3(content) {
  return text2(content);
}
function h2(attrs, children) {
  return element2("h2", attrs, children);
}
function div(attrs, children) {
  return element2("div", attrs, children);
}
function p(attrs, children) {
  return element2("p", attrs, children);
}
function span(attrs, children) {
  return element2("span", attrs, children);
}
function button(attrs, children) {
  return element2("button", attrs, children);
}
function form(attrs, children) {
  return element2("form", attrs, children);
}
function input(attrs) {
  return element2("input", attrs, empty_list);
}
function label(attrs, children) {
  return element2("label", attrs, children);
}
function option(attrs, label2) {
  return element2("option", attrs, toList([text2(label2)]));
}
function select(attrs, children) {
  return element2("select", attrs, children);
}
function textarea(attrs, content) {
  return element2(
    "textarea",
    prepend(property2("value", string3(content)), attrs),
    toList([text2(content)])
  );
}

// build/dev/javascript/lustre/lustre/vdom/patch.mjs
var Patch = class extends CustomType {
  constructor(index4, removed, changes, children) {
    super();
    this.index = index4;
    this.removed = removed;
    this.changes = changes;
    this.children = children;
  }
};
var ReplaceText = class extends CustomType {
  constructor(kind, content) {
    super();
    this.kind = kind;
    this.content = content;
  }
};
var ReplaceInnerHtml = class extends CustomType {
  constructor(kind, inner_html) {
    super();
    this.kind = kind;
    this.inner_html = inner_html;
  }
};
var Update = class extends CustomType {
  constructor(kind, added, removed) {
    super();
    this.kind = kind;
    this.added = added;
    this.removed = removed;
  }
};
var Move = class extends CustomType {
  constructor(kind, key, before) {
    super();
    this.kind = kind;
    this.key = key;
    this.before = before;
  }
};
var Replace = class extends CustomType {
  constructor(kind, index4, with$) {
    super();
    this.kind = kind;
    this.index = index4;
    this.with = with$;
  }
};
var Remove = class extends CustomType {
  constructor(kind, index4) {
    super();
    this.kind = kind;
    this.index = index4;
  }
};
var Insert = class extends CustomType {
  constructor(kind, children, before) {
    super();
    this.kind = kind;
    this.children = children;
    this.before = before;
  }
};
function new$5(index4, removed, changes, children) {
  return new Patch(index4, removed, changes, children);
}
var replace_text_kind = 0;
function replace_text(content) {
  return new ReplaceText(replace_text_kind, content);
}
var replace_inner_html_kind = 1;
function replace_inner_html(inner_html) {
  return new ReplaceInnerHtml(replace_inner_html_kind, inner_html);
}
var update_kind = 2;
function update(added, removed) {
  return new Update(update_kind, added, removed);
}
var move_kind = 3;
function move(key, before) {
  return new Move(move_kind, key, before);
}
var remove_kind = 4;
function remove2(index4) {
  return new Remove(remove_kind, index4);
}
var replace_kind = 5;
function replace2(index4, with$) {
  return new Replace(replace_kind, index4, with$);
}
var insert_kind = 6;
function insert3(children, before) {
  return new Insert(insert_kind, children, before);
}

// build/dev/javascript/lustre/lustre/vdom/diff.mjs
var Diff = class extends CustomType {
  constructor(patch, events) {
    super();
    this.patch = patch;
    this.events = events;
  }
};
var AttributeChange = class extends CustomType {
  constructor(added, removed, events) {
    super();
    this.added = added;
    this.removed = removed;
    this.events = events;
  }
};
function is_controlled(events, namespace, tag, path) {
  if (tag === "input" && namespace === "") {
    return has_dispatched_events(events, path);
  } else if (tag === "select" && namespace === "") {
    return has_dispatched_events(events, path);
  } else if (tag === "textarea" && namespace === "") {
    return has_dispatched_events(events, path);
  } else {
    return false;
  }
}
function diff_attributes(loop$controlled, loop$path, loop$mapper, loop$events, loop$old, loop$new, loop$added, loop$removed) {
  while (true) {
    let controlled = loop$controlled;
    let path = loop$path;
    let mapper = loop$mapper;
    let events = loop$events;
    let old = loop$old;
    let new$8 = loop$new;
    let added = loop$added;
    let removed = loop$removed;
    if (new$8 instanceof Empty) {
      if (old instanceof Empty) {
        return new AttributeChange(added, removed, events);
      } else {
        let $ = old.head;
        if ($ instanceof Event2) {
          let prev = $;
          let old$1 = old.tail;
          let name2 = $.name;
          let removed$1 = prepend(prev, removed);
          let events$1 = remove_event(events, path, name2);
          loop$controlled = controlled;
          loop$path = path;
          loop$mapper = mapper;
          loop$events = events$1;
          loop$old = old$1;
          loop$new = new$8;
          loop$added = added;
          loop$removed = removed$1;
        } else {
          let prev = $;
          let old$1 = old.tail;
          let removed$1 = prepend(prev, removed);
          loop$controlled = controlled;
          loop$path = path;
          loop$mapper = mapper;
          loop$events = events;
          loop$old = old$1;
          loop$new = new$8;
          loop$added = added;
          loop$removed = removed$1;
        }
      }
    } else if (old instanceof Empty) {
      let $ = new$8.head;
      if ($ instanceof Event2) {
        let next = $;
        let new$1 = new$8.tail;
        let name2 = $.name;
        let handler = $.handler;
        let added$1 = prepend(next, added);
        let events$1 = add_event(events, mapper, path, name2, handler);
        loop$controlled = controlled;
        loop$path = path;
        loop$mapper = mapper;
        loop$events = events$1;
        loop$old = old;
        loop$new = new$1;
        loop$added = added$1;
        loop$removed = removed;
      } else {
        let next = $;
        let new$1 = new$8.tail;
        let added$1 = prepend(next, added);
        loop$controlled = controlled;
        loop$path = path;
        loop$mapper = mapper;
        loop$events = events;
        loop$old = old;
        loop$new = new$1;
        loop$added = added$1;
        loop$removed = removed;
      }
    } else {
      let next = new$8.head;
      let remaining_new = new$8.tail;
      let prev = old.head;
      let remaining_old = old.tail;
      let $ = compare3(prev, next);
      if ($ instanceof Lt) {
        if (prev instanceof Event2) {
          let name2 = prev.name;
          let removed$1 = prepend(prev, removed);
          let events$1 = remove_event(events, path, name2);
          loop$controlled = controlled;
          loop$path = path;
          loop$mapper = mapper;
          loop$events = events$1;
          loop$old = remaining_old;
          loop$new = new$8;
          loop$added = added;
          loop$removed = removed$1;
        } else {
          let removed$1 = prepend(prev, removed);
          loop$controlled = controlled;
          loop$path = path;
          loop$mapper = mapper;
          loop$events = events;
          loop$old = remaining_old;
          loop$new = new$8;
          loop$added = added;
          loop$removed = removed$1;
        }
      } else if ($ instanceof Eq) {
        if (next instanceof Attribute) {
          if (prev instanceof Attribute) {
            let _block;
            let $1 = next.name;
            if ($1 === "value") {
              _block = controlled || prev.value !== next.value;
            } else if ($1 === "checked") {
              _block = controlled || prev.value !== next.value;
            } else if ($1 === "selected") {
              _block = controlled || prev.value !== next.value;
            } else {
              _block = prev.value !== next.value;
            }
            let has_changes = _block;
            let _block$1;
            if (has_changes) {
              _block$1 = prepend(next, added);
            } else {
              _block$1 = added;
            }
            let added$1 = _block$1;
            loop$controlled = controlled;
            loop$path = path;
            loop$mapper = mapper;
            loop$events = events;
            loop$old = remaining_old;
            loop$new = remaining_new;
            loop$added = added$1;
            loop$removed = removed;
          } else if (prev instanceof Event2) {
            let name2 = prev.name;
            let added$1 = prepend(next, added);
            let removed$1 = prepend(prev, removed);
            let events$1 = remove_event(events, path, name2);
            loop$controlled = controlled;
            loop$path = path;
            loop$mapper = mapper;
            loop$events = events$1;
            loop$old = remaining_old;
            loop$new = remaining_new;
            loop$added = added$1;
            loop$removed = removed$1;
          } else {
            let added$1 = prepend(next, added);
            let removed$1 = prepend(prev, removed);
            loop$controlled = controlled;
            loop$path = path;
            loop$mapper = mapper;
            loop$events = events;
            loop$old = remaining_old;
            loop$new = remaining_new;
            loop$added = added$1;
            loop$removed = removed$1;
          }
        } else if (next instanceof Property) {
          if (prev instanceof Property) {
            let _block;
            let $1 = next.name;
            if ($1 === "scrollLeft") {
              _block = true;
            } else if ($1 === "scrollRight") {
              _block = true;
            } else if ($1 === "value") {
              _block = controlled || !isEqual2(
                prev.value,
                next.value
              );
            } else if ($1 === "checked") {
              _block = controlled || !isEqual2(
                prev.value,
                next.value
              );
            } else if ($1 === "selected") {
              _block = controlled || !isEqual2(
                prev.value,
                next.value
              );
            } else {
              _block = !isEqual2(prev.value, next.value);
            }
            let has_changes = _block;
            let _block$1;
            if (has_changes) {
              _block$1 = prepend(next, added);
            } else {
              _block$1 = added;
            }
            let added$1 = _block$1;
            loop$controlled = controlled;
            loop$path = path;
            loop$mapper = mapper;
            loop$events = events;
            loop$old = remaining_old;
            loop$new = remaining_new;
            loop$added = added$1;
            loop$removed = removed;
          } else if (prev instanceof Event2) {
            let name2 = prev.name;
            let added$1 = prepend(next, added);
            let removed$1 = prepend(prev, removed);
            let events$1 = remove_event(events, path, name2);
            loop$controlled = controlled;
            loop$path = path;
            loop$mapper = mapper;
            loop$events = events$1;
            loop$old = remaining_old;
            loop$new = remaining_new;
            loop$added = added$1;
            loop$removed = removed$1;
          } else {
            let added$1 = prepend(next, added);
            let removed$1 = prepend(prev, removed);
            loop$controlled = controlled;
            loop$path = path;
            loop$mapper = mapper;
            loop$events = events;
            loop$old = remaining_old;
            loop$new = remaining_new;
            loop$added = added$1;
            loop$removed = removed$1;
          }
        } else if (prev instanceof Event2) {
          let name2 = next.name;
          let handler = next.handler;
          let has_changes = prev.prevent_default.kind !== next.prevent_default.kind || prev.stop_propagation.kind !== next.stop_propagation.kind || prev.immediate !== next.immediate || prev.debounce !== next.debounce || prev.throttle !== next.throttle;
          let _block;
          if (has_changes) {
            _block = prepend(next, added);
          } else {
            _block = added;
          }
          let added$1 = _block;
          let events$1 = add_event(events, mapper, path, name2, handler);
          loop$controlled = controlled;
          loop$path = path;
          loop$mapper = mapper;
          loop$events = events$1;
          loop$old = remaining_old;
          loop$new = remaining_new;
          loop$added = added$1;
          loop$removed = removed;
        } else {
          let name2 = next.name;
          let handler = next.handler;
          let added$1 = prepend(next, added);
          let removed$1 = prepend(prev, removed);
          let events$1 = add_event(events, mapper, path, name2, handler);
          loop$controlled = controlled;
          loop$path = path;
          loop$mapper = mapper;
          loop$events = events$1;
          loop$old = remaining_old;
          loop$new = remaining_new;
          loop$added = added$1;
          loop$removed = removed$1;
        }
      } else if (next instanceof Event2) {
        let name2 = next.name;
        let handler = next.handler;
        let added$1 = prepend(next, added);
        let events$1 = add_event(events, mapper, path, name2, handler);
        loop$controlled = controlled;
        loop$path = path;
        loop$mapper = mapper;
        loop$events = events$1;
        loop$old = old;
        loop$new = remaining_new;
        loop$added = added$1;
        loop$removed = removed;
      } else {
        let added$1 = prepend(next, added);
        loop$controlled = controlled;
        loop$path = path;
        loop$mapper = mapper;
        loop$events = events;
        loop$old = old;
        loop$new = remaining_new;
        loop$added = added$1;
        loop$removed = removed;
      }
    }
  }
}
function do_diff(loop$old, loop$old_keyed, loop$new, loop$new_keyed, loop$moved, loop$moved_offset, loop$removed, loop$node_index, loop$patch_index, loop$path, loop$changes, loop$children, loop$mapper, loop$events) {
  while (true) {
    let old = loop$old;
    let old_keyed = loop$old_keyed;
    let new$8 = loop$new;
    let new_keyed = loop$new_keyed;
    let moved = loop$moved;
    let moved_offset = loop$moved_offset;
    let removed = loop$removed;
    let node_index = loop$node_index;
    let patch_index = loop$patch_index;
    let path = loop$path;
    let changes = loop$changes;
    let children = loop$children;
    let mapper = loop$mapper;
    let events = loop$events;
    if (new$8 instanceof Empty) {
      if (old instanceof Empty) {
        return new Diff(
          new Patch(patch_index, removed, changes, children),
          events
        );
      } else {
        let prev = old.head;
        let old$1 = old.tail;
        let _block;
        let $ = prev.key === "" || !has_key2(moved, prev.key);
        if ($) {
          _block = removed + 1;
        } else {
          _block = removed;
        }
        let removed$1 = _block;
        let events$1 = remove_child(events, path, node_index, prev);
        loop$old = old$1;
        loop$old_keyed = old_keyed;
        loop$new = new$8;
        loop$new_keyed = new_keyed;
        loop$moved = moved;
        loop$moved_offset = moved_offset;
        loop$removed = removed$1;
        loop$node_index = node_index;
        loop$patch_index = patch_index;
        loop$path = path;
        loop$changes = changes;
        loop$children = children;
        loop$mapper = mapper;
        loop$events = events$1;
      }
    } else if (old instanceof Empty) {
      let events$1 = add_children(
        events,
        mapper,
        path,
        node_index,
        new$8
      );
      let insert4 = insert3(new$8, node_index - moved_offset);
      let changes$1 = prepend(insert4, changes);
      return new Diff(
        new Patch(patch_index, removed, changes$1, children),
        events$1
      );
    } else {
      let next = new$8.head;
      let prev = old.head;
      if (prev.key !== next.key) {
        let new_remaining = new$8.tail;
        let old_remaining = old.tail;
        let next_did_exist = get(old_keyed, next.key);
        let prev_does_exist = has_key2(new_keyed, prev.key);
        if (next_did_exist instanceof Ok) {
          if (prev_does_exist) {
            let match = next_did_exist[0];
            let $ = has_key2(moved, prev.key);
            if ($) {
              loop$old = old_remaining;
              loop$old_keyed = old_keyed;
              loop$new = new$8;
              loop$new_keyed = new_keyed;
              loop$moved = moved;
              loop$moved_offset = moved_offset - 1;
              loop$removed = removed;
              loop$node_index = node_index;
              loop$patch_index = patch_index;
              loop$path = path;
              loop$changes = changes;
              loop$children = children;
              loop$mapper = mapper;
              loop$events = events;
            } else {
              let before = node_index - moved_offset;
              let changes$1 = prepend(
                move(next.key, before),
                changes
              );
              let moved$1 = insert2(moved, next.key, void 0);
              let moved_offset$1 = moved_offset + 1;
              loop$old = prepend(match, old);
              loop$old_keyed = old_keyed;
              loop$new = new$8;
              loop$new_keyed = new_keyed;
              loop$moved = moved$1;
              loop$moved_offset = moved_offset$1;
              loop$removed = removed;
              loop$node_index = node_index;
              loop$patch_index = patch_index;
              loop$path = path;
              loop$changes = changes$1;
              loop$children = children;
              loop$mapper = mapper;
              loop$events = events;
            }
          } else {
            let index4 = node_index - moved_offset;
            let changes$1 = prepend(remove2(index4), changes);
            let events$1 = remove_child(events, path, node_index, prev);
            let moved_offset$1 = moved_offset - 1;
            loop$old = old_remaining;
            loop$old_keyed = old_keyed;
            loop$new = new$8;
            loop$new_keyed = new_keyed;
            loop$moved = moved;
            loop$moved_offset = moved_offset$1;
            loop$removed = removed;
            loop$node_index = node_index;
            loop$patch_index = patch_index;
            loop$path = path;
            loop$changes = changes$1;
            loop$children = children;
            loop$mapper = mapper;
            loop$events = events$1;
          }
        } else if (prev_does_exist) {
          let before = node_index - moved_offset;
          let events$1 = add_child(
            events,
            mapper,
            path,
            node_index,
            next
          );
          let insert4 = insert3(toList([next]), before);
          let changes$1 = prepend(insert4, changes);
          loop$old = old;
          loop$old_keyed = old_keyed;
          loop$new = new_remaining;
          loop$new_keyed = new_keyed;
          loop$moved = moved;
          loop$moved_offset = moved_offset + 1;
          loop$removed = removed;
          loop$node_index = node_index + 1;
          loop$patch_index = patch_index;
          loop$path = path;
          loop$changes = changes$1;
          loop$children = children;
          loop$mapper = mapper;
          loop$events = events$1;
        } else {
          let change = replace2(node_index - moved_offset, next);
          let _block;
          let _pipe = events;
          let _pipe$1 = remove_child(_pipe, path, node_index, prev);
          _block = add_child(_pipe$1, mapper, path, node_index, next);
          let events$1 = _block;
          loop$old = old_remaining;
          loop$old_keyed = old_keyed;
          loop$new = new_remaining;
          loop$new_keyed = new_keyed;
          loop$moved = moved;
          loop$moved_offset = moved_offset;
          loop$removed = removed;
          loop$node_index = node_index + 1;
          loop$patch_index = patch_index;
          loop$path = path;
          loop$changes = prepend(change, changes);
          loop$children = children;
          loop$mapper = mapper;
          loop$events = events$1;
        }
      } else {
        let $ = old.head;
        if ($ instanceof Fragment) {
          let $1 = new$8.head;
          if ($1 instanceof Fragment) {
            let next$1 = $1;
            let new$1 = new$8.tail;
            let prev$1 = $;
            let old$1 = old.tail;
            let composed_mapper = compose_mapper(mapper, next$1.mapper);
            let child_path = add2(path, node_index, next$1.key);
            let child = do_diff(
              prev$1.children,
              prev$1.keyed_children,
              next$1.children,
              next$1.keyed_children,
              empty2(),
              0,
              0,
              0,
              node_index,
              child_path,
              empty_list,
              empty_list,
              composed_mapper,
              events
            );
            let _block;
            let $2 = child.patch;
            let $3 = $2.children;
            if ($3 instanceof Empty) {
              let $4 = $2.changes;
              if ($4 instanceof Empty) {
                let $5 = $2.removed;
                if ($5 === 0) {
                  _block = children;
                } else {
                  _block = prepend(child.patch, children);
                }
              } else {
                _block = prepend(child.patch, children);
              }
            } else {
              _block = prepend(child.patch, children);
            }
            let children$1 = _block;
            loop$old = old$1;
            loop$old_keyed = old_keyed;
            loop$new = new$1;
            loop$new_keyed = new_keyed;
            loop$moved = moved;
            loop$moved_offset = moved_offset;
            loop$removed = removed;
            loop$node_index = node_index + 1;
            loop$patch_index = patch_index;
            loop$path = path;
            loop$changes = changes;
            loop$children = children$1;
            loop$mapper = mapper;
            loop$events = child.events;
          } else {
            let next$1 = $1;
            let new_remaining = new$8.tail;
            let prev$1 = $;
            let old_remaining = old.tail;
            let change = replace2(node_index - moved_offset, next$1);
            let _block;
            let _pipe = events;
            let _pipe$1 = remove_child(_pipe, path, node_index, prev$1);
            _block = add_child(
              _pipe$1,
              mapper,
              path,
              node_index,
              next$1
            );
            let events$1 = _block;
            loop$old = old_remaining;
            loop$old_keyed = old_keyed;
            loop$new = new_remaining;
            loop$new_keyed = new_keyed;
            loop$moved = moved;
            loop$moved_offset = moved_offset;
            loop$removed = removed;
            loop$node_index = node_index + 1;
            loop$patch_index = patch_index;
            loop$path = path;
            loop$changes = prepend(change, changes);
            loop$children = children;
            loop$mapper = mapper;
            loop$events = events$1;
          }
        } else if ($ instanceof Element) {
          let $1 = new$8.head;
          if ($1 instanceof Element) {
            let next$1 = $1;
            let prev$1 = $;
            if (prev$1.namespace === next$1.namespace && prev$1.tag === next$1.tag) {
              let new$1 = new$8.tail;
              let old$1 = old.tail;
              let composed_mapper = compose_mapper(
                mapper,
                next$1.mapper
              );
              let child_path = add2(path, node_index, next$1.key);
              let controlled = is_controlled(
                events,
                next$1.namespace,
                next$1.tag,
                child_path
              );
              let $2 = diff_attributes(
                controlled,
                child_path,
                composed_mapper,
                events,
                prev$1.attributes,
                next$1.attributes,
                empty_list,
                empty_list
              );
              let added_attrs;
              let removed_attrs;
              let events$1;
              added_attrs = $2.added;
              removed_attrs = $2.removed;
              events$1 = $2.events;
              let _block;
              if (removed_attrs instanceof Empty && added_attrs instanceof Empty) {
                _block = empty_list;
              } else {
                _block = toList([update(added_attrs, removed_attrs)]);
              }
              let initial_child_changes = _block;
              let child = do_diff(
                prev$1.children,
                prev$1.keyed_children,
                next$1.children,
                next$1.keyed_children,
                empty2(),
                0,
                0,
                0,
                node_index,
                child_path,
                initial_child_changes,
                empty_list,
                composed_mapper,
                events$1
              );
              let _block$1;
              let $3 = child.patch;
              let $4 = $3.children;
              if ($4 instanceof Empty) {
                let $5 = $3.changes;
                if ($5 instanceof Empty) {
                  let $6 = $3.removed;
                  if ($6 === 0) {
                    _block$1 = children;
                  } else {
                    _block$1 = prepend(child.patch, children);
                  }
                } else {
                  _block$1 = prepend(child.patch, children);
                }
              } else {
                _block$1 = prepend(child.patch, children);
              }
              let children$1 = _block$1;
              loop$old = old$1;
              loop$old_keyed = old_keyed;
              loop$new = new$1;
              loop$new_keyed = new_keyed;
              loop$moved = moved;
              loop$moved_offset = moved_offset;
              loop$removed = removed;
              loop$node_index = node_index + 1;
              loop$patch_index = patch_index;
              loop$path = path;
              loop$changes = changes;
              loop$children = children$1;
              loop$mapper = mapper;
              loop$events = child.events;
            } else {
              let next$2 = $1;
              let new_remaining = new$8.tail;
              let prev$2 = $;
              let old_remaining = old.tail;
              let change = replace2(node_index - moved_offset, next$2);
              let _block;
              let _pipe = events;
              let _pipe$1 = remove_child(
                _pipe,
                path,
                node_index,
                prev$2
              );
              _block = add_child(
                _pipe$1,
                mapper,
                path,
                node_index,
                next$2
              );
              let events$1 = _block;
              loop$old = old_remaining;
              loop$old_keyed = old_keyed;
              loop$new = new_remaining;
              loop$new_keyed = new_keyed;
              loop$moved = moved;
              loop$moved_offset = moved_offset;
              loop$removed = removed;
              loop$node_index = node_index + 1;
              loop$patch_index = patch_index;
              loop$path = path;
              loop$changes = prepend(change, changes);
              loop$children = children;
              loop$mapper = mapper;
              loop$events = events$1;
            }
          } else {
            let next$1 = $1;
            let new_remaining = new$8.tail;
            let prev$1 = $;
            let old_remaining = old.tail;
            let change = replace2(node_index - moved_offset, next$1);
            let _block;
            let _pipe = events;
            let _pipe$1 = remove_child(_pipe, path, node_index, prev$1);
            _block = add_child(
              _pipe$1,
              mapper,
              path,
              node_index,
              next$1
            );
            let events$1 = _block;
            loop$old = old_remaining;
            loop$old_keyed = old_keyed;
            loop$new = new_remaining;
            loop$new_keyed = new_keyed;
            loop$moved = moved;
            loop$moved_offset = moved_offset;
            loop$removed = removed;
            loop$node_index = node_index + 1;
            loop$patch_index = patch_index;
            loop$path = path;
            loop$changes = prepend(change, changes);
            loop$children = children;
            loop$mapper = mapper;
            loop$events = events$1;
          }
        } else if ($ instanceof Text) {
          let $1 = new$8.head;
          if ($1 instanceof Text) {
            let next$1 = $1;
            let prev$1 = $;
            if (prev$1.content === next$1.content) {
              let new$1 = new$8.tail;
              let old$1 = old.tail;
              loop$old = old$1;
              loop$old_keyed = old_keyed;
              loop$new = new$1;
              loop$new_keyed = new_keyed;
              loop$moved = moved;
              loop$moved_offset = moved_offset;
              loop$removed = removed;
              loop$node_index = node_index + 1;
              loop$patch_index = patch_index;
              loop$path = path;
              loop$changes = changes;
              loop$children = children;
              loop$mapper = mapper;
              loop$events = events;
            } else {
              let next$2 = $1;
              let new$1 = new$8.tail;
              let old$1 = old.tail;
              let child = new$5(
                node_index,
                0,
                toList([replace_text(next$2.content)]),
                empty_list
              );
              loop$old = old$1;
              loop$old_keyed = old_keyed;
              loop$new = new$1;
              loop$new_keyed = new_keyed;
              loop$moved = moved;
              loop$moved_offset = moved_offset;
              loop$removed = removed;
              loop$node_index = node_index + 1;
              loop$patch_index = patch_index;
              loop$path = path;
              loop$changes = changes;
              loop$children = prepend(child, children);
              loop$mapper = mapper;
              loop$events = events;
            }
          } else {
            let next$1 = $1;
            let new_remaining = new$8.tail;
            let prev$1 = $;
            let old_remaining = old.tail;
            let change = replace2(node_index - moved_offset, next$1);
            let _block;
            let _pipe = events;
            let _pipe$1 = remove_child(_pipe, path, node_index, prev$1);
            _block = add_child(
              _pipe$1,
              mapper,
              path,
              node_index,
              next$1
            );
            let events$1 = _block;
            loop$old = old_remaining;
            loop$old_keyed = old_keyed;
            loop$new = new_remaining;
            loop$new_keyed = new_keyed;
            loop$moved = moved;
            loop$moved_offset = moved_offset;
            loop$removed = removed;
            loop$node_index = node_index + 1;
            loop$patch_index = patch_index;
            loop$path = path;
            loop$changes = prepend(change, changes);
            loop$children = children;
            loop$mapper = mapper;
            loop$events = events$1;
          }
        } else {
          let $1 = new$8.head;
          if ($1 instanceof UnsafeInnerHtml) {
            let next$1 = $1;
            let new$1 = new$8.tail;
            let prev$1 = $;
            let old$1 = old.tail;
            let composed_mapper = compose_mapper(mapper, next$1.mapper);
            let child_path = add2(path, node_index, next$1.key);
            let $2 = diff_attributes(
              false,
              child_path,
              composed_mapper,
              events,
              prev$1.attributes,
              next$1.attributes,
              empty_list,
              empty_list
            );
            let added_attrs;
            let removed_attrs;
            let events$1;
            added_attrs = $2.added;
            removed_attrs = $2.removed;
            events$1 = $2.events;
            let _block;
            if (removed_attrs instanceof Empty && added_attrs instanceof Empty) {
              _block = empty_list;
            } else {
              _block = toList([update(added_attrs, removed_attrs)]);
            }
            let child_changes = _block;
            let _block$1;
            let $3 = prev$1.inner_html === next$1.inner_html;
            if ($3) {
              _block$1 = child_changes;
            } else {
              _block$1 = prepend(
                replace_inner_html(next$1.inner_html),
                child_changes
              );
            }
            let child_changes$1 = _block$1;
            let _block$2;
            if (child_changes$1 instanceof Empty) {
              _block$2 = children;
            } else {
              _block$2 = prepend(
                new$5(node_index, 0, child_changes$1, toList([])),
                children
              );
            }
            let children$1 = _block$2;
            loop$old = old$1;
            loop$old_keyed = old_keyed;
            loop$new = new$1;
            loop$new_keyed = new_keyed;
            loop$moved = moved;
            loop$moved_offset = moved_offset;
            loop$removed = removed;
            loop$node_index = node_index + 1;
            loop$patch_index = patch_index;
            loop$path = path;
            loop$changes = changes;
            loop$children = children$1;
            loop$mapper = mapper;
            loop$events = events$1;
          } else {
            let next$1 = $1;
            let new_remaining = new$8.tail;
            let prev$1 = $;
            let old_remaining = old.tail;
            let change = replace2(node_index - moved_offset, next$1);
            let _block;
            let _pipe = events;
            let _pipe$1 = remove_child(_pipe, path, node_index, prev$1);
            _block = add_child(
              _pipe$1,
              mapper,
              path,
              node_index,
              next$1
            );
            let events$1 = _block;
            loop$old = old_remaining;
            loop$old_keyed = old_keyed;
            loop$new = new_remaining;
            loop$new_keyed = new_keyed;
            loop$moved = moved;
            loop$moved_offset = moved_offset;
            loop$removed = removed;
            loop$node_index = node_index + 1;
            loop$patch_index = patch_index;
            loop$path = path;
            loop$changes = prepend(change, changes);
            loop$children = children;
            loop$mapper = mapper;
            loop$events = events$1;
          }
        }
      }
    }
  }
}
function diff(events, old, new$8) {
  return do_diff(
    toList([old]),
    empty2(),
    toList([new$8]),
    empty2(),
    empty2(),
    0,
    0,
    0,
    0,
    root2,
    empty_list,
    empty_list,
    identity2,
    tick(events)
  );
}

// build/dev/javascript/lustre/lustre/vdom/reconciler.ffi.mjs
var setTimeout = globalThis.setTimeout;
var clearTimeout = globalThis.clearTimeout;
var createElementNS = (ns, name2) => document().createElementNS(ns, name2);
var createTextNode = (data) => document().createTextNode(data);
var createDocumentFragment = () => document().createDocumentFragment();
var insertBefore = (parent, node, reference) => parent.insertBefore(node, reference);
var moveBefore = SUPPORTS_MOVE_BEFORE ? (parent, node, reference) => parent.moveBefore(node, reference) : insertBefore;
var removeChild = (parent, child) => parent.removeChild(child);
var getAttribute = (node, name2) => node.getAttribute(name2);
var setAttribute = (node, name2, value2) => node.setAttribute(name2, value2);
var removeAttribute = (node, name2) => node.removeAttribute(name2);
var addEventListener = (node, name2, handler, options) => node.addEventListener(name2, handler, options);
var removeEventListener = (node, name2, handler) => node.removeEventListener(name2, handler);
var setInnerHtml = (node, innerHtml) => node.innerHTML = innerHtml;
var setData = (node, data) => node.data = data;
var meta = Symbol("lustre");
var MetadataNode = class {
  constructor(kind, parent, node, key) {
    this.kind = kind;
    this.key = key;
    this.parent = parent;
    this.children = [];
    this.node = node;
    this.handlers = /* @__PURE__ */ new Map();
    this.throttles = /* @__PURE__ */ new Map();
    this.debouncers = /* @__PURE__ */ new Map();
  }
  get parentNode() {
    return this.kind === fragment_kind ? this.node.parentNode : this.node;
  }
};
var insertMetadataChild = (kind, parent, node, index4, key) => {
  const child = new MetadataNode(kind, parent, node, key);
  node[meta] = child;
  parent?.children.splice(index4, 0, child);
  return child;
};
var getPath = (node) => {
  let path = "";
  for (let current = node[meta]; current.parent; current = current.parent) {
    if (current.key) {
      path = `${separator_element}${current.key}${path}`;
    } else {
      const index4 = current.parent.children.indexOf(current);
      path = `${separator_element}${index4}${path}`;
    }
  }
  return path.slice(1);
};
var Reconciler = class {
  #root = null;
  #dispatch = () => {
  };
  #useServerEvents = false;
  #exposeKeys = false;
  constructor(root3, dispatch, { useServerEvents = false, exposeKeys = false } = {}) {
    this.#root = root3;
    this.#dispatch = dispatch;
    this.#useServerEvents = useServerEvents;
    this.#exposeKeys = exposeKeys;
  }
  mount(vdom) {
    insertMetadataChild(element_kind, null, this.#root, 0, null);
    this.#insertChild(this.#root, null, this.#root[meta], 0, vdom);
  }
  push(patch) {
    this.#stack.push({ node: this.#root[meta], patch });
    this.#reconcile();
  }
  // PATCHING ------------------------------------------------------------------
  #stack = [];
  #reconcile() {
    const stack = this.#stack;
    while (stack.length) {
      const { node, patch } = stack.pop();
      const { children: childNodes } = node;
      const { changes, removed, children: childPatches } = patch;
      iterate(changes, (change) => this.#patch(node, change));
      if (removed) {
        this.#removeChildren(node, childNodes.length - removed, removed);
      }
      iterate(childPatches, (childPatch) => {
        const child = childNodes[childPatch.index | 0];
        this.#stack.push({ node: child, patch: childPatch });
      });
    }
  }
  #patch(node, change) {
    switch (change.kind) {
      case replace_text_kind:
        this.#replaceText(node, change);
        break;
      case replace_inner_html_kind:
        this.#replaceInnerHtml(node, change);
        break;
      case update_kind:
        this.#update(node, change);
        break;
      case move_kind:
        this.#move(node, change);
        break;
      case remove_kind:
        this.#remove(node, change);
        break;
      case replace_kind:
        this.#replace(node, change);
        break;
      case insert_kind:
        this.#insert(node, change);
        break;
    }
  }
  // CHANGES -------------------------------------------------------------------
  #insert(parent, { children, before }) {
    const fragment3 = createDocumentFragment();
    const beforeEl = this.#getReference(parent, before);
    this.#insertChildren(fragment3, null, parent, before | 0, children);
    insertBefore(parent.parentNode, fragment3, beforeEl);
  }
  #replace(parent, { index: index4, with: child }) {
    this.#removeChildren(parent, index4 | 0, 1);
    const beforeEl = this.#getReference(parent, index4);
    this.#insertChild(parent.parentNode, beforeEl, parent, index4 | 0, child);
  }
  #getReference(node, index4) {
    index4 = index4 | 0;
    const { children } = node;
    const childCount = children.length;
    if (index4 < childCount) {
      return children[index4].node;
    }
    let lastChild = children[childCount - 1];
    if (!lastChild && node.kind !== fragment_kind) return null;
    if (!lastChild) lastChild = node;
    while (lastChild.kind === fragment_kind && lastChild.children.length) {
      lastChild = lastChild.children[lastChild.children.length - 1];
    }
    return lastChild.node.nextSibling;
  }
  #move(parent, { key, before }) {
    before = before | 0;
    const { children, parentNode } = parent;
    const beforeEl = children[before].node;
    let prev = children[before];
    for (let i = before + 1; i < children.length; ++i) {
      const next = children[i];
      children[i] = prev;
      prev = next;
      if (next.key === key) {
        children[before] = next;
        break;
      }
    }
    const { kind, node, children: prevChildren } = prev;
    moveBefore(parentNode, node, beforeEl);
    if (kind === fragment_kind) {
      this.#moveChildren(parentNode, prevChildren, beforeEl);
    }
  }
  #moveChildren(domParent, children, beforeEl) {
    for (let i = 0; i < children.length; ++i) {
      const { kind, node, children: nestedChildren } = children[i];
      moveBefore(domParent, node, beforeEl);
      if (kind === fragment_kind) {
        this.#moveChildren(domParent, nestedChildren, beforeEl);
      }
    }
  }
  #remove(parent, { index: index4 }) {
    this.#removeChildren(parent, index4, 1);
  }
  #removeChildren(parent, index4, count) {
    const { children, parentNode } = parent;
    const deleted = children.splice(index4, count);
    for (let i = 0; i < deleted.length; ++i) {
      const { kind, node, children: nestedChildren } = deleted[i];
      removeChild(parentNode, node);
      this.#removeDebouncers(deleted[i]);
      if (kind === fragment_kind) {
        deleted.push(...nestedChildren);
      }
    }
  }
  #removeDebouncers(node) {
    const { debouncers, children } = node;
    for (const { timeout } of debouncers.values()) {
      if (timeout) {
        clearTimeout(timeout);
      }
    }
    debouncers.clear();
    iterate(children, (child) => this.#removeDebouncers(child));
  }
  #update({ node, handlers, throttles, debouncers }, { added, removed }) {
    iterate(removed, ({ name: name2 }) => {
      if (handlers.delete(name2)) {
        removeEventListener(node, name2, handleEvent);
        this.#updateDebounceThrottle(throttles, name2, 0);
        this.#updateDebounceThrottle(debouncers, name2, 0);
      } else {
        removeAttribute(node, name2);
        SYNCED_ATTRIBUTES[name2]?.removed?.(node, name2);
      }
    });
    iterate(added, (attribute3) => this.#createAttribute(node, attribute3));
  }
  #replaceText({ node }, { content }) {
    setData(node, content ?? "");
  }
  #replaceInnerHtml({ node }, { inner_html }) {
    setInnerHtml(node, inner_html ?? "");
  }
  // INSERT --------------------------------------------------------------------
  #insertChildren(domParent, beforeEl, metaParent, index4, children) {
    iterate(
      children,
      (child) => this.#insertChild(domParent, beforeEl, metaParent, index4++, child)
    );
  }
  #insertChild(domParent, beforeEl, metaParent, index4, vnode) {
    switch (vnode.kind) {
      case element_kind: {
        const node = this.#createElement(metaParent, index4, vnode);
        this.#insertChildren(node, null, node[meta], 0, vnode.children);
        insertBefore(domParent, node, beforeEl);
        break;
      }
      case text_kind: {
        const node = this.#createTextNode(metaParent, index4, vnode);
        insertBefore(domParent, node, beforeEl);
        break;
      }
      case fragment_kind: {
        const head = this.#createTextNode(metaParent, index4, vnode);
        insertBefore(domParent, head, beforeEl);
        this.#insertChildren(
          domParent,
          beforeEl,
          head[meta],
          0,
          vnode.children
        );
        break;
      }
      case unsafe_inner_html_kind: {
        const node = this.#createElement(metaParent, index4, vnode);
        this.#replaceInnerHtml({ node }, vnode);
        insertBefore(domParent, node, beforeEl);
        break;
      }
    }
  }
  #createElement(parent, index4, { kind, key, tag, namespace, attributes }) {
    const node = createElementNS(namespace || NAMESPACE_HTML, tag);
    insertMetadataChild(kind, parent, node, index4, key);
    if (this.#exposeKeys && key) {
      setAttribute(node, "data-lustre-key", key);
    }
    iterate(attributes, (attribute3) => this.#createAttribute(node, attribute3));
    return node;
  }
  #createTextNode(parent, index4, { kind, key, content }) {
    const node = createTextNode(content ?? "");
    insertMetadataChild(kind, parent, node, index4, key);
    return node;
  }
  #createAttribute(node, attribute3) {
    const { debouncers, handlers, throttles } = node[meta];
    const {
      kind,
      name: name2,
      value: value2,
      prevent_default: prevent,
      debounce: debounceDelay,
      throttle: throttleDelay
    } = attribute3;
    switch (kind) {
      case attribute_kind: {
        const valueOrDefault = value2 ?? "";
        if (name2 === "virtual:defaultValue") {
          node.defaultValue = valueOrDefault;
          return;
        }
        if (valueOrDefault !== getAttribute(node, name2)) {
          setAttribute(node, name2, valueOrDefault);
        }
        SYNCED_ATTRIBUTES[name2]?.added?.(node, valueOrDefault);
        break;
      }
      case property_kind:
        node[name2] = value2;
        break;
      case event_kind: {
        if (handlers.has(name2)) {
          removeEventListener(node, name2, handleEvent);
        }
        const passive = prevent.kind === never_kind;
        addEventListener(node, name2, handleEvent, { passive });
        this.#updateDebounceThrottle(throttles, name2, throttleDelay);
        this.#updateDebounceThrottle(debouncers, name2, debounceDelay);
        handlers.set(name2, (event4) => this.#handleEvent(attribute3, event4));
        break;
      }
    }
  }
  #updateDebounceThrottle(map4, name2, delay) {
    const debounceOrThrottle = map4.get(name2);
    if (delay > 0) {
      if (debounceOrThrottle) {
        debounceOrThrottle.delay = delay;
      } else {
        map4.set(name2, { delay });
      }
    } else if (debounceOrThrottle) {
      const { timeout } = debounceOrThrottle;
      if (timeout) {
        clearTimeout(timeout);
      }
      map4.delete(name2);
    }
  }
  #handleEvent(attribute3, event4) {
    const { currentTarget, type } = event4;
    const { debouncers, throttles } = currentTarget[meta];
    const path = getPath(currentTarget);
    const {
      prevent_default: prevent,
      stop_propagation: stop,
      include,
      immediate
    } = attribute3;
    if (prevent.kind === always_kind) event4.preventDefault();
    if (stop.kind === always_kind) event4.stopPropagation();
    if (type === "submit") {
      event4.detail ??= {};
      event4.detail.formData = [
        ...new FormData(event4.target, event4.submitter).entries()
      ];
    }
    const data = this.#useServerEvents ? createServerEvent(event4, include ?? []) : event4;
    const throttle = throttles.get(type);
    if (throttle) {
      const now = Date.now();
      const last2 = throttle.last || 0;
      if (now > last2 + throttle.delay) {
        throttle.last = now;
        throttle.lastEvent = event4;
        this.#dispatch(data, path, type, immediate);
      }
    }
    const debounce = debouncers.get(type);
    if (debounce) {
      clearTimeout(debounce.timeout);
      debounce.timeout = setTimeout(() => {
        if (event4 === throttles.get(type)?.lastEvent) return;
        this.#dispatch(data, path, type, immediate);
      }, debounce.delay);
    }
    if (!throttle && !debounce) {
      this.#dispatch(data, path, type, immediate);
    }
  }
};
var iterate = (list4, callback) => {
  if (Array.isArray(list4)) {
    for (let i = 0; i < list4.length; i++) {
      callback(list4[i]);
    }
  } else if (list4) {
    for (list4; list4.head; list4 = list4.tail) {
      callback(list4.head);
    }
  }
};
var handleEvent = (event4) => {
  const { currentTarget, type } = event4;
  const handler = currentTarget[meta].handlers.get(type);
  handler(event4);
};
var createServerEvent = (event4, include = []) => {
  const data = {};
  if (event4.type === "input" || event4.type === "change") {
    include.push("target.value");
  }
  if (event4.type === "submit") {
    include.push("detail.formData");
  }
  for (const property3 of include) {
    const path = property3.split(".");
    for (let i = 0, input2 = event4, output = data; i < path.length; i++) {
      if (i === path.length - 1) {
        output[path[i]] = input2[path[i]];
        break;
      }
      output = output[path[i]] ??= {};
      input2 = input2[path[i]];
    }
  }
  return data;
};
var syncedBooleanAttribute = /* @__NO_SIDE_EFFECTS__ */ (name2) => {
  return {
    added(node) {
      node[name2] = true;
    },
    removed(node) {
      node[name2] = false;
    }
  };
};
var syncedAttribute = /* @__NO_SIDE_EFFECTS__ */ (name2) => {
  return {
    added(node, value2) {
      node[name2] = value2;
    }
  };
};
var SYNCED_ATTRIBUTES = {
  checked: /* @__PURE__ */ syncedBooleanAttribute("checked"),
  selected: /* @__PURE__ */ syncedBooleanAttribute("selected"),
  value: /* @__PURE__ */ syncedAttribute("value"),
  autofocus: {
    added(node) {
      queueMicrotask(() => {
        node.focus?.();
      });
    }
  },
  autoplay: {
    added(node) {
      try {
        node.play?.();
      } catch (e) {
        console.error(e);
      }
    }
  }
};

// build/dev/javascript/lustre/lustre/element/keyed.mjs
function do_extract_keyed_children(loop$key_children_pairs, loop$keyed_children, loop$children) {
  while (true) {
    let key_children_pairs = loop$key_children_pairs;
    let keyed_children = loop$keyed_children;
    let children = loop$children;
    if (key_children_pairs instanceof Empty) {
      return [keyed_children, reverse(children)];
    } else {
      let rest = key_children_pairs.tail;
      let key = key_children_pairs.head[0];
      let element$1 = key_children_pairs.head[1];
      let keyed_element = to_keyed(key, element$1);
      let _block;
      if (key === "") {
        _block = keyed_children;
      } else {
        _block = insert2(keyed_children, key, keyed_element);
      }
      let keyed_children$1 = _block;
      let children$1 = prepend(keyed_element, children);
      loop$key_children_pairs = rest;
      loop$keyed_children = keyed_children$1;
      loop$children = children$1;
    }
  }
}
function extract_keyed_children(children) {
  return do_extract_keyed_children(
    children,
    empty2(),
    empty_list
  );
}
function element3(tag, attributes, children) {
  let $ = extract_keyed_children(children);
  let keyed_children;
  let children$1;
  keyed_children = $[0];
  children$1 = $[1];
  return element(
    "",
    identity2,
    "",
    tag,
    attributes,
    children$1,
    keyed_children,
    false,
    false
  );
}
function namespaced2(namespace, tag, attributes, children) {
  let $ = extract_keyed_children(children);
  let keyed_children;
  let children$1;
  keyed_children = $[0];
  children$1 = $[1];
  return element(
    "",
    identity2,
    namespace,
    tag,
    attributes,
    children$1,
    keyed_children,
    false,
    false
  );
}
function fragment2(children) {
  let $ = extract_keyed_children(children);
  let keyed_children;
  let children$1;
  keyed_children = $[0];
  children$1 = $[1];
  return fragment("", identity2, children$1, keyed_children);
}

// build/dev/javascript/lustre/lustre/vdom/virtualise.ffi.mjs
var virtualise = (root3) => {
  const rootMeta = insertMetadataChild(element_kind, null, root3, 0, null);
  let virtualisableRootChildren = 0;
  for (let child = root3.firstChild; child; child = child.nextSibling) {
    if (canVirtualiseNode(child)) virtualisableRootChildren += 1;
  }
  if (virtualisableRootChildren === 0) {
    const placeholder = document().createTextNode("");
    insertMetadataChild(text_kind, rootMeta, placeholder, 0, null);
    root3.replaceChildren(placeholder);
    return none2();
  }
  if (virtualisableRootChildren === 1) {
    const children2 = virtualiseChildNodes(rootMeta, root3);
    return children2.head[1];
  }
  const fragmentHead = document().createTextNode("");
  const fragmentMeta = insertMetadataChild(fragment_kind, rootMeta, fragmentHead, 0, null);
  const children = virtualiseChildNodes(fragmentMeta, root3);
  root3.insertBefore(fragmentHead, root3.firstChild);
  return fragment2(children);
};
var canVirtualiseNode = (node) => {
  switch (node.nodeType) {
    case ELEMENT_NODE:
      return true;
    case TEXT_NODE:
      return !!node.data;
    default:
      return false;
  }
};
var virtualiseNode = (meta2, node, key, index4) => {
  if (!canVirtualiseNode(node)) {
    return null;
  }
  switch (node.nodeType) {
    case ELEMENT_NODE: {
      const childMeta = insertMetadataChild(element_kind, meta2, node, index4, key);
      const tag = node.localName;
      const namespace = node.namespaceURI;
      const isHtmlElement = !namespace || namespace === NAMESPACE_HTML;
      if (isHtmlElement && INPUT_ELEMENTS.includes(tag)) {
        virtualiseInputEvents(tag, node);
      }
      const attributes = virtualiseAttributes(node);
      const children = virtualiseChildNodes(childMeta, node);
      const vnode = isHtmlElement ? element3(tag, attributes, children) : namespaced2(namespace, tag, attributes, children);
      return vnode;
    }
    case TEXT_NODE:
      insertMetadataChild(text_kind, meta2, node, index4, null);
      return text2(node.data);
    default:
      return null;
  }
};
var INPUT_ELEMENTS = ["input", "select", "textarea"];
var virtualiseInputEvents = (tag, node) => {
  const value2 = node.value;
  const checked2 = node.checked;
  if (tag === "input" && node.type === "checkbox" && !checked2) return;
  if (tag === "input" && node.type === "radio" && !checked2) return;
  if (node.type !== "checkbox" && node.type !== "radio" && !value2) return;
  queueMicrotask(() => {
    node.value = value2;
    node.checked = checked2;
    node.dispatchEvent(new Event("input", { bubbles: true }));
    node.dispatchEvent(new Event("change", { bubbles: true }));
    if (document().activeElement !== node) {
      node.dispatchEvent(new Event("blur", { bubbles: true }));
    }
  });
};
var virtualiseChildNodes = (meta2, node) => {
  let children = null;
  let child = node.firstChild;
  let ptr = null;
  let index4 = 0;
  while (child) {
    const key = child.nodeType === ELEMENT_NODE ? child.getAttribute("data-lustre-key") : null;
    if (key != null) {
      child.removeAttribute("data-lustre-key");
    }
    const vnode = virtualiseNode(meta2, child, key, index4);
    const next = child.nextSibling;
    if (vnode) {
      const list_node = new NonEmpty([key ?? "", vnode], null);
      if (ptr) {
        ptr = ptr.tail = list_node;
      } else {
        ptr = children = list_node;
      }
      index4 += 1;
    } else {
      node.removeChild(child);
    }
    child = next;
  }
  if (!ptr) return empty_list;
  ptr.tail = empty_list;
  return children;
};
var virtualiseAttributes = (node) => {
  let index4 = node.attributes.length;
  let attributes = empty_list;
  while (index4-- > 0) {
    const attr = node.attributes[index4];
    if (attr.name === "xmlns") {
      continue;
    }
    attributes = new NonEmpty(virtualiseAttribute(attr), attributes);
  }
  return attributes;
};
var virtualiseAttribute = (attr) => {
  const name2 = attr.localName;
  const value2 = attr.value;
  return attribute2(name2, value2);
};

// build/dev/javascript/lustre/lustre/runtime/client/runtime.ffi.mjs
var is_browser = () => !!document();
var Runtime = class {
  constructor(root3, [model, effects], view3, update3) {
    this.root = root3;
    this.#model = model;
    this.#view = view3;
    this.#update = update3;
    this.root.addEventListener("context-request", (event4) => {
      if (!(event4.context && event4.callback)) return;
      if (!this.#contexts.has(event4.context)) return;
      event4.stopImmediatePropagation();
      const context = this.#contexts.get(event4.context);
      if (event4.subscribe) {
        const callbackRef = new WeakRef(event4.callback);
        const unsubscribe = () => {
          context.subscribers = context.subscribers.filter(
            (subscriber) => subscriber !== callbackRef
          );
        };
        context.subscribers.push([callbackRef, unsubscribe]);
        event4.callback(context.value, unsubscribe);
      } else {
        event4.callback(context.value);
      }
    });
    this.#reconciler = new Reconciler(this.root, (event4, path, name2) => {
      const [events, result] = handle(this.#events, path, name2, event4);
      this.#events = events;
      if (result.isOk()) {
        const handler = result[0];
        if (handler.stop_propagation) event4.stopPropagation();
        if (handler.prevent_default) event4.preventDefault();
        this.dispatch(handler.message, false);
      }
    });
    this.#vdom = virtualise(this.root);
    this.#events = new$3();
    this.#shouldFlush = true;
    this.#tick(effects);
  }
  // PUBLIC API ----------------------------------------------------------------
  root = null;
  dispatch(msg, immediate = false) {
    this.#shouldFlush ||= immediate;
    if (this.#shouldQueue) {
      this.#queue.push(msg);
    } else {
      const [model, effects] = this.#update(this.#model, msg);
      this.#model = model;
      this.#tick(effects);
    }
  }
  emit(event4, data) {
    const target = this.root.host ?? this.root;
    target.dispatchEvent(
      new CustomEvent(event4, {
        detail: data,
        bubbles: true,
        composed: true
      })
    );
  }
  // Provide a context value for any child nodes that request it using the given
  // key. If the key already exists, any existing subscribers will be notified
  // of the change. Otherwise, we store the value and wait for any `context-request`
  // events to come in.
  provide(key, value2) {
    if (!this.#contexts.has(key)) {
      this.#contexts.set(key, { value: value2, subscribers: [] });
    } else {
      const context = this.#contexts.get(key);
      context.value = value2;
      for (let i = context.subscribers.length - 1; i >= 0; i--) {
        const [subscriberRef, unsubscribe] = context.subscribers[i];
        const subscriber = subscriberRef.deref();
        if (!subscriber) {
          context.subscribers.splice(i, 1);
          continue;
        }
        subscriber(value2, unsubscribe);
      }
    }
  }
  // PRIVATE API ---------------------------------------------------------------
  #model;
  #view;
  #update;
  #vdom;
  #events;
  #reconciler;
  #contexts = /* @__PURE__ */ new Map();
  #shouldQueue = false;
  #queue = [];
  #beforePaint = empty_list;
  #afterPaint = empty_list;
  #renderTimer = null;
  #shouldFlush = false;
  #actions = {
    dispatch: (msg, immediate) => this.dispatch(msg, immediate),
    emit: (event4, data) => this.emit(event4, data),
    select: () => {
    },
    root: () => this.root,
    provide: (key, value2) => this.provide(key, value2)
  };
  // A `#tick` is where we process effects and trigger any synchronous updates.
  // Once a tick has been processed a render will be scheduled if none is already.
  // p0
  #tick(effects) {
    this.#shouldQueue = true;
    while (true) {
      for (let list4 = effects.synchronous; list4.tail; list4 = list4.tail) {
        list4.head(this.#actions);
      }
      this.#beforePaint = listAppend(this.#beforePaint, effects.before_paint);
      this.#afterPaint = listAppend(this.#afterPaint, effects.after_paint);
      if (!this.#queue.length) break;
      [this.#model, effects] = this.#update(this.#model, this.#queue.shift());
    }
    this.#shouldQueue = false;
    if (this.#shouldFlush) {
      cancelAnimationFrame(this.#renderTimer);
      this.#render();
    } else if (!this.#renderTimer) {
      this.#renderTimer = requestAnimationFrame(() => {
        this.#render();
      });
    }
  }
  #render() {
    this.#shouldFlush = false;
    this.#renderTimer = null;
    const next = this.#view(this.#model);
    const { patch, events } = diff(this.#events, this.#vdom, next);
    this.#events = events;
    this.#vdom = next;
    this.#reconciler.push(patch);
    if (this.#beforePaint instanceof NonEmpty) {
      const effects = makeEffect(this.#beforePaint);
      this.#beforePaint = empty_list;
      queueMicrotask(() => {
        this.#shouldFlush = true;
        this.#tick(effects);
      });
    }
    if (this.#afterPaint instanceof NonEmpty) {
      const effects = makeEffect(this.#afterPaint);
      this.#afterPaint = empty_list;
      requestAnimationFrame(() => {
        this.#shouldFlush = true;
        this.#tick(effects);
      });
    }
  }
};
function makeEffect(synchronous) {
  return {
    synchronous,
    after_paint: empty_list,
    before_paint: empty_list
  };
}
function listAppend(a, b) {
  if (a instanceof Empty) {
    return b;
  } else if (b instanceof Empty) {
    return a;
  } else {
    return append(a, b);
  }
}

// build/dev/javascript/lustre/lustre/runtime/server/runtime.mjs
var EffectDispatchedMessage = class extends CustomType {
  constructor(message) {
    super();
    this.message = message;
  }
};
var EffectEmitEvent = class extends CustomType {
  constructor(name2, data) {
    super();
    this.name = name2;
    this.data = data;
  }
};
var SystemRequestedShutdown = class extends CustomType {
};

// build/dev/javascript/lustre/lustre/component.mjs
var Config2 = class extends CustomType {
  constructor(open_shadow_root, adopt_styles, delegates_focus, attributes, properties, contexts, is_form_associated, on_form_autofill, on_form_reset, on_form_restore) {
    super();
    this.open_shadow_root = open_shadow_root;
    this.adopt_styles = adopt_styles;
    this.delegates_focus = delegates_focus;
    this.attributes = attributes;
    this.properties = properties;
    this.contexts = contexts;
    this.is_form_associated = is_form_associated;
    this.on_form_autofill = on_form_autofill;
    this.on_form_reset = on_form_reset;
    this.on_form_restore = on_form_restore;
  }
};
function new$6(options) {
  let init2 = new Config2(
    true,
    true,
    false,
    empty_list,
    empty_list,
    empty_list,
    false,
    option_none,
    option_none,
    option_none
  );
  return fold2(
    options,
    init2,
    (config, option2) => {
      return option2.apply(config);
    }
  );
}

// build/dev/javascript/lustre/lustre/runtime/client/spa.ffi.mjs
var Spa = class {
  #runtime;
  constructor(root3, [init2, effects], update3, view3) {
    this.#runtime = new Runtime(root3, [init2, effects], view3, update3);
  }
  send(message) {
    switch (message.constructor) {
      case EffectDispatchedMessage: {
        this.dispatch(message.message, false);
        break;
      }
      case EffectEmitEvent: {
        this.emit(message.name, message.data);
        break;
      }
      case SystemRequestedShutdown:
        break;
    }
  }
  dispatch(msg, immediate) {
    this.#runtime.dispatch(msg, immediate);
  }
  emit(event4, data) {
    this.#runtime.emit(event4, data);
  }
};
var start = ({ init: init2, update: update3, view: view3 }, selector, flags) => {
  if (!is_browser()) return new Error(new NotABrowser());
  const root3 = selector instanceof HTMLElement ? selector : document().querySelector(selector);
  if (!root3) return new Error(new ElementNotFound(selector));
  return new Ok(new Spa(root3, init2(flags), update3, view3));
};

// build/dev/javascript/lustre/lustre.mjs
var App = class extends CustomType {
  constructor(init2, update3, view3, config) {
    super();
    this.init = init2;
    this.update = update3;
    this.view = view3;
    this.config = config;
  }
};
var ElementNotFound = class extends CustomType {
  constructor(selector) {
    super();
    this.selector = selector;
  }
};
var NotABrowser = class extends CustomType {
};
function application(init2, update3, view3) {
  return new App(init2, update3, view3, new$6(empty_list));
}
function start3(app, selector, start_args) {
  return guard(
    !is_browser(),
    new Error(new NotABrowser()),
    () => {
      return start(app, selector, start_args);
    }
  );
}

// build/dev/javascript/formosh/schema/types.mjs
var JsonString = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var JsonNumber = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var JsonInteger = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var JsonBool = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var JsonNull = class extends CustomType {
};
var JsonArray = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var JsonObject = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var StringType = class extends CustomType {
};
var NumberType = class extends CustomType {
};
var IntegerType = class extends CustomType {
};
var BooleanType = class extends CustomType {
};
var ArrayType = class extends CustomType {
};
var ObjectType = class extends CustomType {
};
var NullType = class extends CustomType {
};
var StringConstraints = class extends CustomType {
  constructor(min_length, max_length, pattern, format) {
    super();
    this.min_length = min_length;
    this.max_length = max_length;
    this.pattern = pattern;
    this.format = format;
  }
};
var DateFormat = class extends CustomType {
};
var DateTimeFormat = class extends CustomType {
};
var TimeFormat = class extends CustomType {
};
var EmailFormat = class extends CustomType {
};
var UriFormat = class extends CustomType {
};
var UrlFormat = class extends CustomType {
};
var UuidFormat = class extends CustomType {
};
var CustomFormat = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var NumberConstraints = class extends CustomType {
  constructor(minimum, maximum, exclusive_minimum, exclusive_maximum, multiple_of) {
    super();
    this.minimum = minimum;
    this.maximum = maximum;
    this.exclusive_minimum = exclusive_minimum;
    this.exclusive_maximum = exclusive_maximum;
    this.multiple_of = multiple_of;
  }
};
var SchemaProperty = class extends CustomType {
  constructor(field_type, title, description, default$, enum_values, string_constraints, number_constraints, items, properties, required2) {
    super();
    this.field_type = field_type;
    this.title = title;
    this.description = description;
    this.default = default$;
    this.enum_values = enum_values;
    this.string_constraints = string_constraints;
    this.number_constraints = number_constraints;
    this.items = items;
    this.properties = properties;
    this.required = required2;
  }
};
var JsonSchema = class extends CustomType {
  constructor(title, description, field_type, properties, required2, string_constraints, number_constraints) {
    super();
    this.title = title;
    this.description = description;
    this.field_type = field_type;
    this.properties = properties;
    this.required = required2;
    this.string_constraints = string_constraints;
    this.number_constraints = number_constraints;
  }
};
var ValidationError = class extends CustomType {
  constructor(field2, message, rule) {
    super();
    this.field = field2;
    this.message = message;
    this.rule = rule;
  }
};
var StringValue = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var NumberValue = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var IntegerValue = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var BooleanValue = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var ArrayValue = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var ObjectValue = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var NullValue = class extends CustomType {
};

// build/dev/javascript/formosh/form/path.mjs
var PropertySegment = class extends CustomType {
  constructor(name2) {
    super();
    this.name = name2;
  }
};
var ArraySegment = class extends CustomType {
  constructor(index4) {
    super();
    this.index = index4;
  }
};
function from_field_name(field_name) {
  return toList([new PropertySegment(field_name)]);
}
function to_array_item_field(array_name, index4, field_name) {
  return toList([
    new PropertySegment(array_name),
    new ArraySegment(index4),
    new PropertySegment(field_name)
  ]);
}
function to_string4(path) {
  let _pipe = path;
  let _pipe$1 = map(
    _pipe,
    (segment) => {
      if (segment instanceof PropertySegment) {
        let name2 = segment.name;
        return name2;
      } else {
        let index4 = segment.index;
        return "[" + to_string(index4) + "]";
      }
    }
  );
  return join(_pipe$1, ".");
}
function get_field_name(path) {
  let $ = last(path);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof PropertySegment) {
      let name2 = $1.name;
      return new Some(name2);
    } else {
      return new None();
    }
  } else {
    return new None();
  }
}
function get_object_fields(value2) {
  if (value2 instanceof ObjectValue) {
    let fields = value2[0];
    return fields;
  } else {
    return toList([]);
  }
}
function get_array_items(value2) {
  if (value2 instanceof ArrayValue) {
    let items = value2[0];
    return items;
  } else {
    return toList([]);
  }
}
function ensure_array_size(items, size2) {
  let current = length(items);
  let $ = size2 > current;
  if ($) {
    return append(
      items,
      repeat(new JsonNull(), size2 - current)
    );
  } else {
    return items;
  }
}
function json_to_field_value(json2) {
  if (json2 instanceof JsonString) {
    let s = json2[0];
    return new Some(new StringValue(s));
  } else if (json2 instanceof JsonNumber) {
    let n = json2[0];
    return new Some(new NumberValue(n));
  } else if (json2 instanceof JsonInteger) {
    let i = json2[0];
    return new Some(new IntegerValue(i));
  } else if (json2 instanceof JsonBool) {
    let b = json2[0];
    return new Some(new BooleanValue(b));
  } else if (json2 instanceof JsonNull) {
    return new Some(new NullValue());
  } else if (json2 instanceof JsonArray) {
    let items = json2[0];
    return new Some(new ArrayValue(items));
  } else {
    let fields = json2[0];
    return new Some(new ObjectValue(fields));
  }
}
function json_to_field_value_safe(json2) {
  let _pipe = json_to_field_value(json2);
  return unwrap(_pipe, new NullValue());
}
function get_field_value(fields, name2) {
  let $ = find2(fields, (f) => {
    return f[0] === name2;
  });
  if ($ instanceof Ok) {
    let json2 = $[0][1];
    return json_to_field_value_safe(json2);
  } else {
    return new NullValue();
  }
}
function field_to_json_value(value2) {
  if (value2 instanceof StringValue) {
    let s = value2[0];
    return new JsonString(s);
  } else if (value2 instanceof NumberValue) {
    let n = value2[0];
    return new JsonNumber(n);
  } else if (value2 instanceof IntegerValue) {
    let i = value2[0];
    return new JsonInteger(i);
  } else if (value2 instanceof BooleanValue) {
    let b = value2[0];
    return new JsonBool(b);
  } else if (value2 instanceof ArrayValue) {
    let items = value2[0];
    return new JsonArray(items);
  } else if (value2 instanceof ObjectValue) {
    let fields = value2[0];
    return new JsonObject(fields);
  } else {
    return new JsonNull();
  }
}
function modify_array_item(value2, index4, modifier) {
  let items = get_array_items(value2);
  let padded = ensure_array_size(items, index4 + 1);
  let updated = index_map(
    padded,
    (item, i) => {
      let $ = i === index4;
      if ($) {
        return field_to_json_value(modifier(json_to_field_value_safe(item)));
      } else {
        return item;
      }
    }
  );
  return new ArrayValue(updated);
}
function set_field_value(fields, name2, value2) {
  let json_value = field_to_json_value(value2);
  let $ = find2(fields, (f) => {
    return f[0] === name2;
  });
  if ($ instanceof Ok) {
    return map(
      fields,
      (field2) => {
        let $1 = field2[0] === name2;
        if ($1) {
          return [name2, json_value];
        } else {
          return field2;
        }
      }
    );
  } else {
    return append(fields, toList([[name2, json_value]]));
  }
}
function modify_object_field(value2, field_name, modifier) {
  let fields = get_object_fields(value2);
  let current_value = get_field_value(fields, field_name);
  let new_value = modifier(current_value);
  let updated_fields = set_field_value(fields, field_name, new_value);
  return new ObjectValue(updated_fields);
}
function modify_at_path(root3, path, modifier) {
  if (path instanceof Empty) {
    return modifier(root3);
  } else {
    let segment = path.head;
    let rest = path.tail;
    if (segment instanceof PropertySegment) {
      let name2 = segment.name;
      return modify_object_field(
        root3,
        name2,
        (field_value) => {
          return modify_at_path(field_value, rest, modifier);
        }
      );
    } else {
      let index4 = segment.index;
      return modify_array_item(
        root3,
        index4,
        (item_value) => {
          return modify_at_path(item_value, rest, modifier);
        }
      );
    }
  }
}
function set_at_path(root3, path, value2) {
  return modify_at_path(root3, path, (_) => {
    return value2;
  });
}
function add_array_item_at_path(root3, path, item) {
  return modify_at_path(
    root3,
    path,
    (value2) => {
      if (value2 instanceof ArrayValue) {
        let items = value2[0];
        return new ArrayValue(append(items, toList([item])));
      } else {
        return new ArrayValue(toList([item]));
      }
    }
  );
}
function remove_array_item_at_path(root3, path, index4) {
  return modify_at_path(
    root3,
    path,
    (value2) => {
      if (value2 instanceof ArrayValue) {
        let items = value2[0];
        let filtered = index_fold(
          items,
          toList([]),
          (acc, item, i) => {
            let $ = i === index4;
            if ($) {
              return acc;
            } else {
              return append(acc, toList([item]));
            }
          }
        );
        return new ArrayValue(filtered);
      } else {
        return value2;
      }
    }
  );
}

// build/dev/javascript/formosh/form/model.mjs
var FormModel = class extends CustomType {
  constructor(schema, values3, errors, is_submitting, is_dirty, is_valid, touched_fields, disabled_fields, submission_result) {
    super();
    this.schema = schema;
    this.values = values3;
    this.errors = errors;
    this.is_submitting = is_submitting;
    this.is_dirty = is_dirty;
    this.is_valid = is_valid;
    this.touched_fields = touched_fields;
    this.disabled_fields = disabled_fields;
    this.submission_result = submission_result;
  }
};
var SubmissionSuccess = class extends CustomType {
  constructor(message) {
    super();
    this.message = message;
  }
};
var SubmissionError = class extends CustomType {
  constructor(message) {
    super();
    this.message = message;
  }
};
var UpdateFieldPath = class extends CustomType {
  constructor(path, value2) {
    super();
    this.path = path;
    this.value = value2;
  }
};
var AddArrayItemPath = class extends CustomType {
  constructor(path) {
    super();
    this.path = path;
  }
};
var RemoveArrayItemPath = class extends CustomType {
  constructor(path, index4) {
    super();
    this.path = path;
    this.index = index4;
  }
};
var FormSubmit = class extends CustomType {
};
var FormSubmitted = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var ValidateForm = class extends CustomType {
};
var ResetForm = class extends CustomType {
};
function init(schema) {
  return new FormModel(
    schema,
    new_map(),
    new_map(),
    false,
    false,
    true,
    toList([]),
    toList([]),
    new None()
  );
}
function is_field_required(model, field_name) {
  return contains(model.schema.required, field_name);
}
function field_has_errors(model, field_name) {
  let $ = map_get(model.errors, field_name);
  if ($ instanceof Ok) {
    let errors = $[0];
    return length(errors) > 0;
  } else {
    return false;
  }
}
function is_field_touched(model, field_name) {
  return contains(model.touched_fields, field_name);
}
function is_field_disabled(model, field_name) {
  return contains(model.disabled_fields, field_name);
}
function get_field_value2(model, field_name) {
  let $ = map_get(model.values, field_name);
  if ($ instanceof Ok) {
    let value2 = $[0];
    return new Some(value2);
  } else {
    return new None();
  }
}
function get_field_errors(model, field_name) {
  let $ = map_get(model.errors, field_name);
  if ($ instanceof Ok) {
    let errors = $[0];
    return errors;
  } else {
    return toList([]);
  }
}
function add_field_error(model, field_name, error) {
  let current_errors = get_field_errors(model, field_name);
  let new_errors = append(current_errors, toList([error]));
  return new FormModel(
    model.schema,
    model.values,
    insert(model.errors, field_name, new_errors),
    model.is_submitting,
    model.is_dirty,
    false,
    model.touched_fields,
    model.disabled_fields,
    model.submission_result
  );
}
function clear_field_errors(model, field_name) {
  return new FormModel(
    model.schema,
    model.values,
    delete$(model.errors, field_name),
    model.is_submitting,
    model.is_dirty,
    map_size(model.errors) === 1,
    model.touched_fields,
    model.disabled_fields,
    model.submission_result
  );
}
function clear_all_errors(model) {
  return new FormModel(
    model.schema,
    model.values,
    new_map(),
    model.is_submitting,
    model.is_dirty,
    true,
    model.touched_fields,
    model.disabled_fields,
    model.submission_result
  );
}
function reset(model) {
  return new FormModel(
    model.schema,
    new_map(),
    new_map(),
    false,
    false,
    true,
    toList([]),
    toList([]),
    new None()
  );
}
function can_submit(model) {
  return model.is_valid && !model.is_submitting && model.is_dirty;
}

// build/dev/javascript/formosh/schema/validator.mjs
function validate_number_constraints(field_name, value2, constraints) {
  if (constraints instanceof Some) {
    let c = constraints[0];
    let errors = toList([]);
    let _block;
    let $ = c.minimum;
    if ($ instanceof Some) {
      let min3 = $[0];
      let $12 = value2 < min3;
      if ($12) {
        _block = append(
          errors,
          toList([
            new ValidationError(
              field_name,
              "Must be at least " + float_to_string(min3),
              "minimum"
            )
          ])
        );
      } else {
        _block = errors;
      }
    } else {
      _block = errors;
    }
    let errors$1 = _block;
    let _block$1;
    let $1 = c.maximum;
    if ($1 instanceof Some) {
      let max3 = $1[0];
      let $22 = value2 > max3;
      if ($22) {
        _block$1 = append(
          errors$1,
          toList([
            new ValidationError(
              field_name,
              "Must be at most " + float_to_string(max3),
              "maximum"
            )
          ])
        );
      } else {
        _block$1 = errors$1;
      }
    } else {
      _block$1 = errors$1;
    }
    let errors$2 = _block$1;
    let _block$2;
    let $2 = c.exclusive_minimum;
    if ($2 instanceof Some) {
      let min3 = $2[0];
      let $32 = value2 <= min3;
      if ($32) {
        _block$2 = append(
          errors$2,
          toList([
            new ValidationError(
              field_name,
              "Must be greater than " + float_to_string(min3),
              "exclusiveMinimum"
            )
          ])
        );
      } else {
        _block$2 = errors$2;
      }
    } else {
      _block$2 = errors$2;
    }
    let errors$3 = _block$2;
    let _block$3;
    let $3 = c.exclusive_maximum;
    if ($3 instanceof Some) {
      let max3 = $3[0];
      let $4 = value2 >= max3;
      if ($4) {
        _block$3 = append(
          errors$3,
          toList([
            new ValidationError(
              field_name,
              "Must be less than " + float_to_string(max3),
              "exclusiveMaximum"
            )
          ])
        );
      } else {
        _block$3 = errors$3;
      }
    } else {
      _block$3 = errors$3;
    }
    let errors$4 = _block$3;
    return errors$4;
  } else {
    return toList([]);
  }
}
function validate_number(field_name, value2, constraints) {
  if (value2 instanceof NumberValue) {
    let num = value2[0];
    return validate_number_constraints(field_name, num, constraints);
  } else if (value2 instanceof IntegerValue) {
    let num = value2[0];
    return validate_number_constraints(
      field_name,
      identity(num),
      constraints
    );
  } else {
    return toList([new ValidationError(field_name, "Must be a number", "type")]);
  }
}
function validate_boolean(field_name, value2) {
  if (value2 instanceof BooleanValue) {
    return toList([]);
  } else {
    return toList([
      new ValidationError(field_name, "Must be true or false", "type")
    ]);
  }
}
function validate_enum(_, _1, _2) {
  return toList([]);
}
function validate_email(email) {
  return contains_string(email, "@") && contains_string(email, ".");
}
function validate_url(url) {
  return starts_with(url, "http://") || starts_with(
    url,
    "https://"
  );
}
function validate_string(field_name, value2, constraints) {
  if (value2 instanceof StringValue) {
    let str = value2[0];
    if (constraints instanceof Some) {
      let c = constraints[0];
      let errors = toList([]);
      let _block;
      let $ = c.min_length;
      if ($ instanceof Some) {
        let min3 = $[0];
        let $12 = string_length(str) < min3;
        if ($12) {
          _block = append(
            errors,
            toList([
              new ValidationError(
                field_name,
                "Must be at least " + to_string(min3) + " characters",
                "minLength"
              )
            ])
          );
        } else {
          _block = errors;
        }
      } else {
        _block = errors;
      }
      let errors$1 = _block;
      let _block$1;
      let $1 = c.max_length;
      if ($1 instanceof Some) {
        let max3 = $1[0];
        let $22 = string_length(str) > max3;
        if ($22) {
          _block$1 = append(
            errors$1,
            toList([
              new ValidationError(
                field_name,
                "Must be at most " + to_string(max3) + " characters",
                "maxLength"
              )
            ])
          );
        } else {
          _block$1 = errors$1;
        }
      } else {
        _block$1 = errors$1;
      }
      let errors$2 = _block$1;
      let _block$2;
      let $2 = c.pattern;
      if ($2 instanceof Some) {
        _block$2 = errors$2;
      } else {
        _block$2 = errors$2;
      }
      let errors$3 = _block$2;
      let _block$3;
      let $3 = c.format;
      if ($3 instanceof Some) {
        let $4 = $3[0];
        if ($4 instanceof EmailFormat) {
          let $5 = validate_email(str);
          if ($5) {
            _block$3 = errors$3;
          } else {
            _block$3 = append(
              errors$3,
              toList([
                new ValidationError(
                  field_name,
                  "Invalid email address",
                  "format"
                )
              ])
            );
          }
        } else if ($4 instanceof UriFormat) {
          let $5 = validate_url(str);
          if ($5) {
            _block$3 = errors$3;
          } else {
            _block$3 = append(
              errors$3,
              toList([new ValidationError(field_name, "Invalid URL", "format")])
            );
          }
        } else if ($4 instanceof UrlFormat) {
          let $5 = validate_url(str);
          if ($5) {
            _block$3 = errors$3;
          } else {
            _block$3 = append(
              errors$3,
              toList([new ValidationError(field_name, "Invalid URL", "format")])
            );
          }
        } else {
          _block$3 = errors$3;
        }
      } else {
        _block$3 = errors$3;
      }
      let errors$4 = _block$3;
      return errors$4;
    } else {
      return toList([]);
    }
  } else {
    return toList([new ValidationError(field_name, "Must be a string", "type")]);
  }
}
function validate_field(field_name, value2, property3, is_required) {
  let errors = toList([]);
  let _block;
  if (is_required) {
    if (value2 instanceof Some) {
      let $ = value2[0];
      if ($ instanceof StringValue) {
        let $1 = $[0];
        if ($1 === "") {
          _block = append(
            errors,
            toList([
              new ValidationError(
                field_name,
                "This field is required",
                "required"
              )
            ])
          );
        } else {
          _block = errors;
        }
      } else if ($ instanceof NullValue) {
        _block = append(
          errors,
          toList([
            new ValidationError(
              field_name,
              "This field is required",
              "required"
            )
          ])
        );
      } else {
        _block = errors;
      }
    } else {
      _block = append(
        errors,
        toList([
          new ValidationError(field_name, "This field is required", "required")
        ])
      );
    }
  } else {
    _block = errors;
  }
  let errors$1 = _block;
  if (value2 instanceof Some) {
    let $ = value2[0];
    if ($ instanceof NullValue) {
      return errors$1;
    } else {
      let val = $;
      let _block$1;
      let $1 = property3.field_type;
      if ($1 instanceof Some) {
        let $22 = $1[0];
        if ($22 instanceof StringType) {
          _block$1 = validate_string(
            field_name,
            val,
            property3.string_constraints
          );
        } else if ($22 instanceof NumberType) {
          _block$1 = validate_number(
            field_name,
            val,
            property3.number_constraints
          );
        } else if ($22 instanceof IntegerType) {
          _block$1 = validate_number(
            field_name,
            val,
            property3.number_constraints
          );
        } else if ($22 instanceof BooleanType) {
          _block$1 = validate_boolean(field_name, val);
        } else {
          _block$1 = toList([]);
        }
      } else {
        _block$1 = toList([]);
      }
      let type_errors = _block$1;
      let _block$2;
      let $2 = property3.enum_values;
      if ($2 instanceof Some) {
        let allowed_values = $2[0];
        _block$2 = validate_enum(field_name, val, allowed_values);
      } else {
        _block$2 = toList([]);
      }
      let enum_errors = _block$2;
      return flatten(toList([errors$1, type_errors, enum_errors]));
    }
  } else {
    return errors$1;
  }
}

// build/dev/javascript/formosh/form/update.mjs
function field_value_to_json_value(value2) {
  if (value2 instanceof StringValue) {
    let s = value2[0];
    return new JsonString(s);
  } else if (value2 instanceof NumberValue) {
    let n = value2[0];
    return new JsonNumber(n);
  } else if (value2 instanceof IntegerValue) {
    let i = value2[0];
    return new JsonInteger(i);
  } else if (value2 instanceof BooleanValue) {
    let b = value2[0];
    return new JsonBool(b);
  } else if (value2 instanceof ArrayValue) {
    let items = value2[0];
    return new JsonArray(items);
  } else if (value2 instanceof ObjectValue) {
    let fields = value2[0];
    return new JsonObject(fields);
  } else {
    return new JsonNull();
  }
}
function json_value_to_field_value(value2) {
  if (value2 instanceof JsonString) {
    let s = value2[0];
    return new Some(new StringValue(s));
  } else if (value2 instanceof JsonNumber) {
    let n = value2[0];
    return new Some(new NumberValue(n));
  } else if (value2 instanceof JsonInteger) {
    let i = value2[0];
    return new Some(new IntegerValue(i));
  } else if (value2 instanceof JsonBool) {
    let b = value2[0];
    return new Some(new BooleanValue(b));
  } else if (value2 instanceof JsonNull) {
    return new Some(new NullValue());
  } else if (value2 instanceof JsonArray) {
    let items = value2[0];
    return new Some(new ArrayValue(items));
  } else {
    let fields = value2[0];
    return new Some(new ObjectValue(fields));
  }
}
function validate_field2(model, field_name) {
  let $ = map_get(model.schema.properties, field_name);
  if ($ instanceof Ok) {
    let property3 = $[0];
    let value2 = get_field_value2(model, field_name);
    let errors = validate_field(
      field_name,
      value2,
      property3,
      is_field_required(model, field_name)
    );
    if (errors instanceof Empty) {
      return clear_field_errors(model, field_name);
    } else {
      return fold2(
        errors,
        clear_field_errors(model, field_name),
        (acc, error) => {
          return add_field_error(acc, field_name, error);
        }
      );
    }
  } else {
    return model;
  }
}
function validate_all_fields(model) {
  let _pipe = keys(model.schema.properties);
  return fold2(_pipe, clear_all_errors(model), validate_field2);
}
function submit_form_effect(_) {
  return from(
    (dispatch) => {
      dispatch(new FormSubmitted(new Ok("Form submitted successfully!")));
      return void 0;
    }
  );
}
function update2(model, msg) {
  if (msg instanceof UpdateFieldPath) {
    let path = msg.path;
    let value2 = msg.value;
    let _block;
    let $ = map_to_list(model.values);
    if ($ instanceof Empty) {
      _block = new ObjectValue(toList([]));
    } else {
      let values3 = $;
      let fields = map(
        values3,
        (entry) => {
          let key;
          let val;
          key = entry[0];
          val = entry[1];
          return [key, field_value_to_json_value(val)];
        }
      );
      _block = new ObjectValue(fields);
    }
    let root_value = _block;
    let updated_root = set_at_path(root_value, path, value2);
    let _block$1;
    if (updated_root instanceof ObjectValue) {
      let fields = updated_root[0];
      _block$1 = fold2(
        fields,
        new_map(),
        (acc, field2) => {
          let key;
          let json_val;
          key = field2[0];
          json_val = field2[1];
          let $1 = json_value_to_field_value(json_val);
          if ($1 instanceof Some) {
            let field_val = $1[0];
            return insert(acc, key, field_val);
          } else {
            return acc;
          }
        }
      );
    } else {
      _block$1 = model.values;
    }
    let new_values = _block$1;
    let new_model = new FormModel(
      model.schema,
      new_values,
      model.errors,
      model.is_submitting,
      true,
      model.is_valid,
      model.touched_fields,
      model.disabled_fields,
      model.submission_result
    );
    return [new_model, none()];
  } else if (msg instanceof AddArrayItemPath) {
    let path = msg.path;
    let _block;
    let $ = map_to_list(model.values);
    if ($ instanceof Empty) {
      _block = new ObjectValue(toList([]));
    } else {
      let values3 = $;
      let fields = map(
        values3,
        (entry) => {
          let key;
          let val;
          key = entry[0];
          val = entry[1];
          return [key, field_value_to_json_value(val)];
        }
      );
      _block = new ObjectValue(fields);
    }
    let root_value = _block;
    let updated_root = add_array_item_at_path(
      root_value,
      path,
      new JsonObject(toList([]))
    );
    let _block$1;
    if (updated_root instanceof ObjectValue) {
      let fields = updated_root[0];
      _block$1 = fold2(
        fields,
        new_map(),
        (acc, field2) => {
          let key;
          let json_val;
          key = field2[0];
          json_val = field2[1];
          let $1 = json_value_to_field_value(json_val);
          if ($1 instanceof Some) {
            let field_val = $1[0];
            return insert(acc, key, field_val);
          } else {
            return acc;
          }
        }
      );
    } else {
      _block$1 = model.values;
    }
    let new_values = _block$1;
    let new_model = new FormModel(
      model.schema,
      new_values,
      model.errors,
      model.is_submitting,
      model.is_dirty,
      model.is_valid,
      model.touched_fields,
      model.disabled_fields,
      model.submission_result
    );
    return [new_model, none()];
  } else if (msg instanceof RemoveArrayItemPath) {
    let path = msg.path;
    let index4 = msg.index;
    let _block;
    let $ = map_to_list(model.values);
    if ($ instanceof Empty) {
      _block = new ObjectValue(toList([]));
    } else {
      let values3 = $;
      let fields = map(
        values3,
        (entry) => {
          let key;
          let val;
          key = entry[0];
          val = entry[1];
          return [key, field_value_to_json_value(val)];
        }
      );
      _block = new ObjectValue(fields);
    }
    let root_value = _block;
    let updated_root = remove_array_item_at_path(root_value, path, index4);
    let _block$1;
    if (updated_root instanceof ObjectValue) {
      let fields = updated_root[0];
      _block$1 = fold2(
        fields,
        new_map(),
        (acc, field2) => {
          let key;
          let json_val;
          key = field2[0];
          json_val = field2[1];
          let $1 = json_value_to_field_value(json_val);
          if ($1 instanceof Some) {
            let field_val = $1[0];
            return insert(acc, key, field_val);
          } else {
            return acc;
          }
        }
      );
    } else {
      _block$1 = model.values;
    }
    let new_values = _block$1;
    let new_model = new FormModel(
      model.schema,
      new_values,
      model.errors,
      model.is_submitting,
      model.is_dirty,
      model.is_valid,
      model.touched_fields,
      model.disabled_fields,
      model.submission_result
    );
    return [new_model, none()];
  } else if (msg instanceof FormSubmit) {
    let validated_model = validate_all_fields(model);
    let $ = can_submit(validated_model);
    if ($) {
      let submitting_model = new FormModel(
        validated_model.schema,
        validated_model.values,
        validated_model.errors,
        true,
        validated_model.is_dirty,
        validated_model.is_valid,
        validated_model.touched_fields,
        validated_model.disabled_fields,
        validated_model.submission_result
      );
      let submit_effect = submit_form_effect(submitting_model);
      return [submitting_model, submit_effect];
    } else {
      return [validated_model, none()];
    }
  } else if (msg instanceof FormSubmitted) {
    let result = msg[0];
    if (result instanceof Ok) {
      let message = result[0];
      let new_model = new FormModel(
        model.schema,
        model.values,
        model.errors,
        false,
        model.is_dirty,
        model.is_valid,
        model.touched_fields,
        model.disabled_fields,
        new Some(new SubmissionSuccess(message))
      );
      return [new_model, none()];
    } else {
      let message = result[0];
      let new_model = new FormModel(
        model.schema,
        model.values,
        model.errors,
        false,
        model.is_dirty,
        model.is_valid,
        model.touched_fields,
        model.disabled_fields,
        new Some(new SubmissionError(message))
      );
      return [new_model, none()];
    }
  } else if (msg instanceof ValidateForm) {
    let new_model = validate_all_fields(model);
    return [new_model, none()];
  } else {
    let new_model = reset(model);
    return [new_model, none()];
  }
}

// build/dev/javascript/gleam_stdlib/gleam/pair.mjs
function new$7(first, second) {
  return [first, second];
}

// build/dev/javascript/lustre/lustre/event.mjs
function is_immediate_event(name2) {
  if (name2 === "input") {
    return true;
  } else if (name2 === "change") {
    return true;
  } else if (name2 === "focus") {
    return true;
  } else if (name2 === "focusin") {
    return true;
  } else if (name2 === "focusout") {
    return true;
  } else if (name2 === "blur") {
    return true;
  } else if (name2 === "select") {
    return true;
  } else {
    return false;
  }
}
function on(name2, handler) {
  return event(
    name2,
    map2(handler, (msg) => {
      return new Handler(false, false, msg);
    }),
    empty_list,
    never,
    never,
    is_immediate_event(name2),
    0,
    0
  );
}
function prevent_default(event4) {
  if (event4 instanceof Event2) {
    return new Event2(
      event4.kind,
      event4.name,
      event4.handler,
      event4.include,
      always,
      event4.stop_propagation,
      event4.immediate,
      event4.debounce,
      event4.throttle
    );
  } else {
    return event4;
  }
}
function on_click(msg) {
  return on("click", success(msg));
}
function on_input(msg) {
  return on(
    "input",
    subfield(
      toList(["target", "value"]),
      string2,
      (value2) => {
        return success(msg(value2));
      }
    )
  );
}
function on_change(msg) {
  return on(
    "change",
    subfield(
      toList(["target", "value"]),
      string2,
      (value2) => {
        return success(msg(value2));
      }
    )
  );
}
function formdata_decoder() {
  let string_value_decoder = field(
    0,
    string2,
    (key) => {
      return field(
        1,
        one_of(
          map2(string2, (var0) => {
            return new Ok(var0);
          }),
          toList([success(new Error(void 0))])
        ),
        (value2) => {
          let _pipe2 = value2;
          let _pipe$12 = map3(
            _pipe2,
            (_capture) => {
              return new$7(key, _capture);
            }
          );
          return success(_pipe$12);
        }
      );
    }
  );
  let _pipe = string_value_decoder;
  let _pipe$1 = list2(_pipe);
  return map2(_pipe$1, values2);
}
function on_submit(msg) {
  let _pipe = on(
    "submit",
    subfield(
      toList(["detail", "formData"]),
      formdata_decoder(),
      (formdata) => {
        let _pipe2 = formdata;
        let _pipe$1 = msg(_pipe2);
        return success(_pipe$1);
      }
    )
  );
  return prevent_default(_pipe);
}

// build/dev/javascript/formosh/fields/boolean_field.mjs
function render_label(field_name, property3, is_required) {
  let _block;
  let $ = property3.title;
  if ($ instanceof Some) {
    let title = $[0];
    _block = title;
  } else {
    let _pipe = field_name;
    let _pipe$1 = replace(_pipe, "_", " ");
    _block = capitalise(_pipe$1);
  }
  let label_text = _block;
  return label(
    toList([for$(field_name), class$("formosh-label")]),
    toList([
      text3(label_text),
      (() => {
        if (is_required) {
          return span(
            toList([class$("formosh-required")]),
            toList([text3(" *")])
          );
        } else {
          return text3("");
        }
      })()
    ])
  );
}
function render_help_text(property3) {
  let $ = property3.description;
  if ($ instanceof Some) {
    let desc = $[0];
    return div(
      toList([class$("formosh-help")]),
      toList([text3(desc)])
    );
  } else {
    return text3("");
  }
}
function render_as_radio(field_path, property3, current_value, is_required, is_disabled) {
  let _block;
  let _pipe = get_field_name(field_path);
  _block = unwrap(_pipe, "field");
  let field_name = _block;
  let yes_id = field_name + "_yes";
  let no_id = field_name + "_no";
  return div(
    toList([class$("formosh-field-wrapper")]),
    toList([
      render_label(field_name, property3, is_required),
      div(
        toList([class$("formosh-radio-group formosh-boolean")]),
        toList([
          div(
            toList([class$("formosh-radio-item")]),
            toList([
              input(
                toList([
                  type_("radio"),
                  id(yes_id),
                  name(field_name),
                  value("true"),
                  checked(current_value),
                  required(is_required),
                  disabled(is_disabled),
                  on_click(
                    new UpdateFieldPath(
                      field_path,
                      new BooleanValue(true)
                    )
                  )
                ])
              ),
              label(
                toList([for$(yes_id)]),
                toList([text3("Yes")])
              )
            ])
          ),
          div(
            toList([class$("formosh-radio-item")]),
            toList([
              input(
                toList([
                  type_("radio"),
                  id(no_id),
                  name(field_name),
                  value("false"),
                  checked(!current_value),
                  required(is_required),
                  disabled(is_disabled),
                  on_click(
                    new UpdateFieldPath(
                      field_path,
                      new BooleanValue(false)
                    )
                  )
                ])
              ),
              label(
                toList([for$(no_id)]),
                toList([text3("No")])
              )
            ])
          )
        ])
      ),
      render_help_text(property3)
    ])
  );
}
function render(field_path, property3, value2, is_required, is_disabled) {
  let _block;
  if (value2 instanceof Some) {
    let $ = value2[0];
    if ($ instanceof BooleanValue) {
      let b = $[0];
      _block = b;
    } else {
      _block = false;
    }
  } else {
    _block = false;
  }
  let current_value = _block;
  return render_as_radio(
    field_path,
    property3,
    current_value,
    is_required,
    is_disabled
  );
}

// build/dev/javascript/formosh/fields/number_field.mjs
function handle_number_input(field_path, value2, is_integer) {
  if (value2 === "") {
    return new UpdateFieldPath(field_path, new NullValue());
  } else {
    let str = value2;
    if (is_integer) {
      let $ = parse_int(str);
      if ($ instanceof Ok) {
        let i = $[0];
        return new UpdateFieldPath(field_path, new IntegerValue(i));
      } else {
        return new UpdateFieldPath(field_path, new StringValue(str));
      }
    } else {
      let $ = parse_float(str);
      if ($ instanceof Ok) {
        let f = $[0];
        return new UpdateFieldPath(field_path, new NumberValue(f));
      } else {
        let $1 = parse_int(str);
        if ($1 instanceof Ok) {
          let i = $1[0];
          return new UpdateFieldPath(
            field_path,
            new NumberValue(identity(i))
          );
        } else {
          return new UpdateFieldPath(field_path, new StringValue(str));
        }
      }
    }
  }
}
function render_label2(field_name, property3, is_required) {
  let _block;
  let $ = property3.title;
  if ($ instanceof Some) {
    let title = $[0];
    _block = title;
  } else {
    let _pipe = field_name;
    let _pipe$1 = replace(_pipe, "_", " ");
    _block = capitalise(_pipe$1);
  }
  let label_text = _block;
  return label(
    toList([for$(field_name), class$("formosh-label")]),
    toList([
      text3(label_text),
      (() => {
        if (is_required) {
          return span(
            toList([class$("formosh-required")]),
            toList([text3(" *")])
          );
        } else {
          return text3("");
        }
      })()
    ])
  );
}
function render_help_text2(property3) {
  let $ = property3.description;
  if ($ instanceof Some) {
    let desc = $[0];
    return div(
      toList([class$("formosh-help")]),
      toList([text3(desc)])
    );
  } else {
    return text3("");
  }
}
function get_number_constraints_attributes(property3) {
  let $ = property3.number_constraints;
  if ($ instanceof Some) {
    let constraints = $[0];
    let attrs = toList([]);
    let _block;
    let $1 = constraints.minimum;
    if ($1 instanceof Some) {
      let min3 = $1[0];
      _block = append(
        attrs,
        toList([min2(float_to_string(min3))])
      );
    } else {
      _block = attrs;
    }
    let attrs$1 = _block;
    let _block$1;
    let $2 = constraints.maximum;
    if ($2 instanceof Some) {
      let max3 = $2[0];
      _block$1 = append(
        attrs$1,
        toList([max2(float_to_string(max3))])
      );
    } else {
      _block$1 = attrs$1;
    }
    let attrs$2 = _block$1;
    let _block$2;
    let $3 = constraints.exclusive_minimum;
    if ($3 instanceof Some) {
      let min3 = $3[0];
      let adjusted = min3 + 1e-6;
      _block$2 = append(
        attrs$2,
        toList([min2(float_to_string(adjusted))])
      );
    } else {
      _block$2 = attrs$2;
    }
    let attrs$3 = _block$2;
    let _block$3;
    let $4 = constraints.exclusive_maximum;
    if ($4 instanceof Some) {
      let max3 = $4[0];
      let adjusted = max3 - 1e-6;
      _block$3 = append(
        attrs$3,
        toList([max2(float_to_string(adjusted))])
      );
    } else {
      _block$3 = attrs$3;
    }
    let attrs$4 = _block$3;
    let _block$4;
    let $5 = constraints.multiple_of;
    if ($5 instanceof Some) {
      let step2 = $5[0];
      _block$4 = append(
        attrs$4,
        toList([step(float_to_string(step2))])
      );
    } else {
      _block$4 = attrs$4;
    }
    let attrs$5 = _block$4;
    return attrs$5;
  } else {
    return toList([]);
  }
}
function render2(field_path, property3, value2, is_required, is_disabled) {
  let _block;
  let $ = property3.field_type;
  if ($ instanceof Some) {
    let $1 = $[0];
    if ($1 instanceof IntegerType) {
      _block = true;
    } else {
      _block = false;
    }
  } else {
    _block = false;
  }
  let is_integer = _block;
  let _block$1;
  if (value2 instanceof Some) {
    let $1 = value2[0];
    if ($1 instanceof NumberValue) {
      let n = $1[0];
      _block$1 = float_to_string(n);
    } else if ($1 instanceof IntegerValue) {
      let i = $1[0];
      _block$1 = to_string(i);
    } else {
      _block$1 = "";
    }
  } else {
    _block$1 = "";
  }
  let current_value = _block$1;
  let _block$2;
  let _pipe = get_field_name(field_path);
  _block$2 = unwrap(_pipe, "field");
  let field_name = _block$2;
  return div(
    toList([class$("formosh-field-wrapper")]),
    toList([
      render_label2(field_name, property3, is_required),
      input(
        prepend(
          id(to_string4(field_path)),
          prepend(
            name(field_name),
            prepend(
              type_("number"),
              prepend(
                value(current_value),
                prepend(
                  class$("formosh-input formosh-number"),
                  prepend(
                    required(is_required),
                    prepend(
                      disabled(is_disabled),
                      prepend(
                        (() => {
                          if (is_integer) {
                            return step("1");
                          } else {
                            return step("any");
                          }
                        })(),
                        prepend(
                          on_input(
                            (val) => {
                              return handle_number_input(
                                field_path,
                                val,
                                is_integer
                              );
                            }
                          ),
                          get_number_constraints_attributes(property3)
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      ),
      render_help_text2(property3)
    ])
  );
}

// build/dev/javascript/formosh/fields/field_common.mjs
function render_label3(field_name, property3, is_required) {
  let _block;
  let $ = property3.title;
  if ($ instanceof Some) {
    let title = $[0];
    _block = title;
  } else {
    let _pipe = field_name;
    let _pipe$1 = replace(_pipe, "_", " ");
    _block = capitalise(_pipe$1);
  }
  let label_text = _block;
  return label(
    toList([for$(field_name), class$("formosh-label")]),
    toList([
      text3(label_text),
      (() => {
        if (is_required) {
          return span(
            toList([class$("formosh-required")]),
            toList([text3(" *")])
          );
        } else {
          return text3("");
        }
      })()
    ])
  );
}
function render_help_text3(property3) {
  let $ = property3.description;
  if ($ instanceof Some) {
    let desc = $[0];
    return div(
      toList([class$("formosh-help")]),
      toList([text3(desc)])
    );
  } else {
    return text3("");
  }
}
function field_wrapper(field_name, property3, is_required, field_element) {
  return div(
    toList([class$("formosh-field-wrapper")]),
    toList([
      render_label3(field_name, property3, is_required),
      field_element,
      render_help_text3(property3)
    ])
  );
}
function input_attributes_with_path(field_path, value2, is_required, is_disabled, extra_attrs) {
  let _block;
  let _pipe = get_field_name(field_path);
  _block = unwrap(_pipe, "field");
  let field_name = _block;
  return prepend(
    id(to_string4(field_path)),
    prepend(
      name(field_name),
      prepend(
        value(value2),
        prepend(
          required(is_required),
          prepend(
            disabled(is_disabled),
            prepend(
              on_input(
                (val) => {
                  return new UpdateFieldPath(
                    field_path,
                    new StringValue(val)
                  );
                }
              ),
              extra_attrs
            )
          )
        )
      )
    )
  );
}

// build/dev/javascript/formosh/fields/string_field.mjs
function get_input_type(property3) {
  let $ = property3.string_constraints;
  if ($ instanceof Some) {
    let constraints = $[0];
    let $1 = constraints.format;
    if ($1 instanceof Some) {
      let $2 = $1[0];
      if ($2 instanceof DateFormat) {
        return "date";
      } else if ($2 instanceof DateTimeFormat) {
        return "datetime-local";
      } else if ($2 instanceof TimeFormat) {
        return "time";
      } else if ($2 instanceof EmailFormat) {
        return "email";
      } else if ($2 instanceof UrlFormat) {
        return "url";
      } else {
        return "text";
      }
    } else {
      return "text";
    }
  } else {
    return "text";
  }
}
function get_string_constraints_attributes(property3) {
  let $ = property3.string_constraints;
  if ($ instanceof Some) {
    let constraints = $[0];
    let attrs = toList([]);
    let _block;
    let $1 = constraints.min_length;
    if ($1 instanceof Some) {
      let min3 = $1[0];
      _block = append(
        attrs,
        toList([attribute2("minlength", to_string(min3))])
      );
    } else {
      _block = attrs;
    }
    let attrs$1 = _block;
    let _block$1;
    let $2 = constraints.max_length;
    if ($2 instanceof Some) {
      let max3 = $2[0];
      _block$1 = append(
        attrs$1,
        toList([attribute2("maxlength", to_string(max3))])
      );
    } else {
      _block$1 = attrs$1;
    }
    let attrs$2 = _block$1;
    let _block$2;
    let $3 = constraints.pattern;
    if ($3 instanceof Some) {
      let pattern = $3[0];
      _block$2 = append(
        attrs$2,
        toList([attribute2("pattern", pattern)])
      );
    } else {
      _block$2 = attrs$2;
    }
    let attrs$3 = _block$2;
    return attrs$3;
  } else {
    return toList([]);
  }
}
function render_input(field_path, property3, value2, is_required, is_disabled) {
  let _block;
  if (value2 instanceof Some) {
    let $ = value2[0];
    if ($ instanceof StringValue) {
      let s = $[0];
      _block = s;
    } else {
      _block = "";
    }
  } else {
    _block = "";
  }
  let current_value = _block;
  let input_type = get_input_type(property3);
  let extra_attrs = prepend(
    type_(input_type),
    prepend(
      class$("formosh-input"),
      get_string_constraints_attributes(property3)
    )
  );
  let _block$1;
  let _pipe = get_field_name(field_path);
  _block$1 = unwrap(_pipe, "field");
  let field_name = _block$1;
  let input_elem = input(
    input_attributes_with_path(
      field_path,
      current_value,
      is_required,
      is_disabled,
      extra_attrs
    )
  );
  return field_wrapper(
    field_name,
    property3,
    is_required,
    input_elem
  );
}
function render_textarea(field_path, property3, value2, is_required, is_disabled) {
  let _block;
  if (value2 instanceof Some) {
    let $ = value2[0];
    if ($ instanceof StringValue) {
      let s = $[0];
      _block = s;
    } else {
      _block = "";
    }
  } else {
    _block = "";
  }
  let current_value = _block;
  let extra_attrs = prepend(
    class$("formosh-textarea"),
    get_string_constraints_attributes(property3)
  );
  let _block$1;
  let _pipe = get_field_name(field_path);
  _block$1 = unwrap(_pipe, "field");
  let field_name = _block$1;
  let textarea_elem = textarea(
    input_attributes_with_path(
      field_path,
      current_value,
      is_required,
      is_disabled,
      extra_attrs
    ),
    current_value
  );
  return field_wrapper(
    field_name,
    property3,
    is_required,
    textarea_elem
  );
}
function json_value_to_string(val) {
  if (val instanceof JsonString) {
    let s = val[0];
    return s;
  } else if (val instanceof JsonNumber) {
    let n = val[0];
    return float_to_string(n);
  } else if (val instanceof JsonInteger) {
    let i = val[0];
    return to_string(i);
  } else if (val instanceof JsonBool) {
    let $ = val[0];
    if ($) {
      return "true";
    } else {
      return "false";
    }
  } else if (val instanceof JsonNull) {
    return "";
  } else {
    return "";
  }
}
function render_radio_group(field_path, property3, enum_vals, current_value, is_required, is_disabled) {
  let _block;
  let _pipe = get_field_name(field_path);
  _block = unwrap(_pipe, "field");
  let field_name = _block;
  let radio_group = div(
    toList([class$("formosh-radio-group")]),
    map(
      enum_vals,
      (val) => {
        let str_val = json_value_to_string(val);
        let radio_id = field_name + "_" + str_val;
        return div(
          toList([class$("formosh-radio-item")]),
          toList([
            input(
              toList([
                type_("radio"),
                id(radio_id),
                name(field_name),
                value(str_val),
                checked(str_val === current_value),
                required(is_required),
                disabled(is_disabled),
                on_click(
                  new UpdateFieldPath(
                    field_path,
                    new StringValue(str_val)
                  )
                )
              ])
            ),
            label(
              toList([for$(radio_id)]),
              toList([text3(str_val)])
            )
          ])
        );
      }
    )
  );
  return field_wrapper(
    field_name,
    property3,
    is_required,
    radio_group
  );
}
function render_select(field_path, property3, enum_vals, current_value, is_required, is_disabled) {
  let _block;
  let _pipe = get_field_name(field_path);
  _block = unwrap(_pipe, "field");
  let field_name = _block;
  let select_elem = select(
    toList([
      id(field_name),
      name(field_name),
      class$("formosh-select"),
      required(is_required),
      disabled(is_disabled),
      on_change(
        (val) => {
          return new UpdateFieldPath(field_path, new StringValue(val));
        }
      )
    ]),
    prepend(
      option(toList([value("")]), "Select an option..."),
      map(
        enum_vals,
        (val) => {
          let str_val = json_value_to_string(val);
          return option(
            toList([
              value(str_val),
              selected(str_val === current_value)
            ]),
            str_val
          );
        }
      )
    )
  );
  return field_wrapper(
    field_name,
    property3,
    is_required,
    select_elem
  );
}
function render_enum(field_path, property3, value2, is_required, is_disabled) {
  let $ = property3.enum_values;
  if ($ instanceof Some) {
    let enum_vals = $[0];
    let _block;
    if (value2 instanceof Some) {
      let $12 = value2[0];
      if ($12 instanceof StringValue) {
        let s = $12[0];
        _block = s;
      } else {
        _block = "";
      }
    } else {
      _block = "";
    }
    let current_value = _block;
    let $1 = length(enum_vals) <= 5;
    if ($1) {
      return render_radio_group(
        field_path,
        property3,
        enum_vals,
        current_value,
        is_required,
        is_disabled
      );
    } else {
      return render_select(
        field_path,
        property3,
        enum_vals,
        current_value,
        is_required,
        is_disabled
      );
    }
  } else {
    return text3("");
  }
}
function render3(field_path, property3, value2, is_required, is_disabled) {
  let $ = property3.enum_values;
  if ($ instanceof Some) {
    return render_enum(field_path, property3, value2, is_required, is_disabled);
  } else {
    let $1 = property3.string_constraints;
    if ($1 instanceof Some) {
      let constraints = $1[0];
      let $2 = constraints.max_length;
      if ($2 instanceof Some) {
        let max3 = $2[0];
        if (max3 > 100) {
          return render_textarea(
            field_path,
            property3,
            value2,
            is_required,
            is_disabled
          );
        } else {
          return render_input(
            field_path,
            property3,
            value2,
            is_required,
            is_disabled
          );
        }
      } else {
        return render_input(
          field_path,
          property3,
          value2,
          is_required,
          is_disabled
        );
      }
    } else {
      return render_input(field_path, property3, value2, is_required, is_disabled);
    }
  }
}

// build/dev/javascript/formosh/fields/array_field.mjs
function render_field(array_name, index4, field_name, property3, value2, required2) {
  let field_path = to_array_item_field(array_name, index4, field_name);
  let _block;
  let $ = property3.field_type;
  if ($ instanceof Some) {
    let $1 = $[0];
    if ($1 instanceof StringType) {
      _block = render3(
        field_path,
        property3,
        new Some(value2),
        required2,
        false
      );
    } else if ($1 instanceof NumberType) {
      _block = render2(
        field_path,
        property3,
        new Some(value2),
        required2,
        false
      );
    } else if ($1 instanceof IntegerType) {
      _block = render2(
        field_path,
        property3,
        new Some(value2),
        required2,
        false
      );
    } else if ($1 instanceof BooleanType) {
      _block = render(
        field_path,
        property3,
        new Some(value2),
        required2,
        false
      );
    } else {
      _block = div(
        toList([class$("unsupported-field")]),
        toList([text3("Unsupported field type")])
      );
    }
  } else {
    _block = div(
      toList([class$("unsupported-field")]),
      toList([text3("Unsupported field type")])
    );
  }
  let field_element = _block;
  return div(
    toList([class$("array-item-field")]),
    toList([field_element])
  );
}
function render_item_fields(array_name, item_schema, item_values, index4) {
  let $ = item_schema.properties;
  if ($ instanceof Some) {
    let props = $[0];
    let _pipe = map_to_list(props);
    return map(
      _pipe,
      (entry) => {
        let field_name;
        let field_prop;
        field_name = entry[0];
        field_prop = entry[1];
        let _block;
        let _pipe$1 = map_get(item_values, field_name);
        _block = unwrap2(_pipe$1, new NullValue());
        let value2 = _block;
        return render_field(
          array_name,
          index4,
          field_name,
          field_prop,
          value2,
          contains(item_schema.required, field_name)
        );
      }
    );
  } else {
    return toList([]);
  }
}
function render_array_item(array_name, property3, item_values, index4) {
  let $ = property3.items;
  if ($ instanceof Some) {
    let item_schema = $[0];
    return div(
      toList([class$("array-item")]),
      toList([
        div(
          toList([class$("array-item-header")]),
          toList([
            span(
              toList([class$("array-item-index")]),
              toList([text3("\u2116 " + to_string(index4 + 1))])
            ),
            button(
              toList([
                type_("button"),
                class$("remove-array-item"),
                on_click(
                  new RemoveArrayItemPath(
                    from_field_name(array_name),
                    index4
                  )
                )
              ]),
              toList([text3("\u0423\u0434\u0430\u043B\u0438\u0442\u044C")])
            )
          ])
        ),
        div(
          toList([class$("array-item-fields")]),
          render_item_fields(array_name, item_schema, item_values, index4)
        )
      ])
    );
  } else {
    return none2();
  }
}
function view(name2, property3, values3, errors, required2) {
  let title = unwrap(property3.title, name2);
  let description = property3.description;
  return div(
    toList([class$("array-field")]),
    toList([
      label(
        toList([class$("array-label")]),
        toList([
          text3(title),
          (() => {
            if (required2) {
              return span(
                toList([class$("required")]),
                toList([text3(" *")])
              );
            } else {
              return none2();
            }
          })()
        ])
      ),
      (() => {
        if (description instanceof Some) {
          let desc = description[0];
          return p(
            toList([class$("field-description")]),
            toList([text3(desc)])
          );
        } else {
          return none2();
        }
      })(),
      div(
        toList([class$("array-items")]),
        index_map(
          values3,
          (item_values, index4) => {
            return render_array_item(name2, property3, item_values, index4);
          }
        )
      ),
      button(
        toList([
          type_("button"),
          class$("add-array-item"),
          on_click(new AddArrayItemPath(from_field_name(name2)))
        ]),
        toList([text3("\u0414\u043E\u0431\u0430\u0432\u0438\u0442\u044C \u044D\u043B\u0435\u043C\u0435\u043D\u0442")])
      ),
      (() => {
        if (errors instanceof Empty) {
          return none2();
        } else {
          let errs = errors;
          return div(
            toList([class$("field-errors")]),
            map(
              errs,
              (err) => {
                return span(
                  toList([class$("error-message")]),
                  toList([text3(err)])
                );
              }
            )
          );
        }
      })()
    ])
  );
}

// build/dev/javascript/formosh/form/view.mjs
function render_form_header(model) {
  return div(
    toList([class$("formosh-header")]),
    toList([
      h2(
        toList([class$("formosh-title")]),
        toList([text3(model.schema.title)])
      ),
      (() => {
        let $ = model.schema.description;
        if ($ instanceof Some) {
          let desc = $[0];
          return p(
            toList([class$("formosh-description")]),
            toList([text3(desc)])
          );
        } else {
          return text3("");
        }
      })()
    ])
  );
}
function render_field_errors(errors) {
  return div(
    toList([class$("formosh-errors")]),
    map(
      errors,
      (error) => {
        return div(
          toList([class$("formosh-error")]),
          toList([text3(error.message)])
        );
      }
    )
  );
}
function render_form_footer(model) {
  return div(
    toList([class$("formosh-footer")]),
    toList([
      button(
        toList([
          type_("submit"),
          class$("formosh-submit"),
          disabled(model.is_submitting || !can_submit(model))
        ]),
        toList([
          text3(
            (() => {
              let $ = model.is_submitting;
              if ($) {
                return "Submitting...";
              } else {
                return "Submit";
              }
            })()
          )
        ])
      ),
      button(
        toList([
          type_("button"),
          class$("formosh-reset"),
          on_click(new ResetForm()),
          disabled(model.is_submitting)
        ]),
        toList([text3("Reset")])
      )
    ])
  );
}
function render_submission_result(model) {
  let $ = model.submission_result;
  if ($ instanceof Some) {
    let $1 = $[0];
    if ($1 instanceof SubmissionSuccess) {
      let message = $1.message;
      return div(
        toList([class$("formosh-success")]),
        toList([text3(message)])
      );
    } else {
      let message = $1.message;
      return div(
        toList([class$("formosh-error-message")]),
        toList([text3(message)])
      );
    }
  } else {
    return text3("");
  }
}
function json_value_to_field_value2(value2) {
  if (value2 instanceof JsonString) {
    let s = value2[0];
    return new StringValue(s);
  } else if (value2 instanceof JsonNumber) {
    let n = value2[0];
    return new NumberValue(n);
  } else if (value2 instanceof JsonInteger) {
    let i = value2[0];
    return new IntegerValue(i);
  } else if (value2 instanceof JsonBool) {
    let b = value2[0];
    return new BooleanValue(b);
  } else if (value2 instanceof JsonNull) {
    return new NullValue();
  } else if (value2 instanceof JsonArray) {
    let items = value2[0];
    return new ArrayValue(items);
  } else {
    let fields = value2[0];
    return new ObjectValue(fields);
  }
}
function render_field2(model, field_name, property3) {
  let is_required = is_field_required(model, field_name);
  let is_disabled = is_field_disabled(model, field_name);
  let is_touched = is_field_touched(model, field_name);
  let has_errors = field_has_errors(model, field_name);
  let errors = get_field_errors(model, field_name);
  let value2 = get_field_value2(model, field_name);
  let field_path = from_field_name(field_name);
  let _block;
  let $ = property3.field_type;
  if ($ instanceof Some) {
    let $1 = $[0];
    if ($1 instanceof StringType) {
      _block = render3(
        field_path,
        property3,
        value2,
        is_required,
        is_disabled
      );
    } else if ($1 instanceof NumberType) {
      _block = render2(
        field_path,
        property3,
        value2,
        is_required,
        is_disabled
      );
    } else if ($1 instanceof IntegerType) {
      _block = render2(
        field_path,
        property3,
        value2,
        is_required,
        is_disabled
      );
    } else if ($1 instanceof BooleanType) {
      _block = render(
        field_path,
        property3,
        value2,
        is_required,
        is_disabled
      );
    } else if ($1 instanceof ArrayType) {
      let _block$1;
      if (value2 instanceof Some) {
        let $2 = value2[0];
        if ($2 instanceof ArrayValue) {
          let items = $2[0];
          _block$1 = map(
            items,
            (item) => {
              if (item instanceof JsonObject) {
                let fields = item[0];
                return fold2(
                  fields,
                  new_map(),
                  (acc, field_pair) => {
                    let key;
                    let val;
                    key = field_pair[0];
                    val = field_pair[1];
                    return insert(
                      acc,
                      key,
                      json_value_to_field_value2(val)
                    );
                  }
                );
              } else {
                return new_map();
              }
            }
          );
        } else {
          _block$1 = toList([]);
        }
      } else {
        _block$1 = toList([]);
      }
      let array_items = _block$1;
      _block = view(
        field_name,
        property3,
        array_items,
        map(errors, (e) => {
          return e.message;
        }),
        is_required
      );
    } else if ($1 instanceof ObjectType) {
      _block = div(
        toList([class$("formosh-field-unsupported")]),
        toList([
          text3("Object field type not yet supported: " + field_name)
        ])
      );
    } else {
      let $2 = property3.enum_values;
      if ($2 instanceof Some) {
        _block = render_enum(
          field_path,
          property3,
          value2,
          is_required,
          is_disabled
        );
      } else {
        _block = div(toList([]), toList([]));
      }
    }
  } else {
    let $1 = property3.enum_values;
    if ($1 instanceof Some) {
      _block = render_enum(
        field_path,
        property3,
        value2,
        is_required,
        is_disabled
      );
    } else {
      _block = div(toList([]), toList([]));
    }
  }
  let field_element = _block;
  return div(
    toList([
      class$(
        "formosh-field" + (() => {
          let $1 = has_errors && is_touched;
          if ($1) {
            return " formosh-field-error";
          } else {
            return "";
          }
        })()
      )
    ]),
    toList([
      field_element,
      (() => {
        let $1 = has_errors && is_touched;
        if ($1) {
          return render_field_errors(errors);
        } else {
          return text3("");
        }
      })()
    ])
  );
}
function render_form_body(model) {
  let _block;
  let _pipe = map_to_list(model.schema.properties);
  _block = map(
    _pipe,
    (pair) => {
      let field_name;
      let property3;
      field_name = pair[0];
      property3 = pair[1];
      return render_field2(model, field_name, property3);
    }
  );
  let fields = _block;
  return form(
    toList([
      class$("formosh-form"),
      on_submit((_) => {
        return new FormSubmit();
      })
    ]),
    fields
  );
}
function view2(model) {
  return div(
    toList([class$("formosh-container")]),
    toList([
      render_form_header(model),
      render_form_body(model),
      render_form_footer(model),
      render_submission_result(model)
    ])
  );
}

// build/dev/javascript/formosh/schema/parser.mjs
var InvalidJson = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var MissingField = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var InvalidType = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var UnexpectedValue = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
var DecodingError = class extends CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
};
function field_type_decoder() {
  let _pipe = string2;
  return then$(
    _pipe,
    (type_str) => {
      if (type_str === "string") {
        return success(new StringType());
      } else if (type_str === "number") {
        return success(new NumberType());
      } else if (type_str === "integer") {
        return success(new IntegerType());
      } else if (type_str === "boolean") {
        return success(new BooleanType());
      } else if (type_str === "null") {
        return success(new NullType());
      } else if (type_str === "array") {
        return success(new ArrayType());
      } else if (type_str === "object") {
        return success(new ObjectType());
      } else {
        return failure(
          new StringType(),
          "Unknown field type: " + type_str
        );
      }
    }
  );
}
function extract_number_constraints(data) {
  let _block;
  let _pipe = run(data, at(toList(["minimum"]), float2));
  _block = from_result(_pipe);
  let minimum = _block;
  let _block$1;
  let _pipe$1 = run(
    data,
    at(toList(["maximum"]), float2)
  );
  _block$1 = from_result(_pipe$1);
  let maximum = _block$1;
  let _block$2;
  let _pipe$2 = run(
    data,
    at(toList(["exclusiveMinimum"]), float2)
  );
  _block$2 = from_result(_pipe$2);
  let exclusive_minimum = _block$2;
  let _block$3;
  let _pipe$3 = run(
    data,
    at(toList(["exclusiveMaximum"]), float2)
  );
  _block$3 = from_result(_pipe$3);
  let exclusive_maximum = _block$3;
  let _block$4;
  let _pipe$4 = run(
    data,
    at(toList(["multipleOf"]), float2)
  );
  _block$4 = from_result(_pipe$4);
  let multiple_of = _block$4;
  if (multiple_of instanceof None && exclusive_maximum instanceof None && exclusive_minimum instanceof None && maximum instanceof None && minimum instanceof None) {
    return minimum;
  } else {
    return new Some(
      new NumberConstraints(
        minimum,
        maximum,
        exclusive_minimum,
        exclusive_maximum,
        multiple_of
      )
    );
  }
}
function format_decoder() {
  let _pipe = string2;
  return then$(
    _pipe,
    (format_str) => {
      if (format_str === "email") {
        return success(new EmailFormat());
      } else if (format_str === "url") {
        return success(new UrlFormat());
      } else if (format_str === "uri") {
        return success(new UrlFormat());
      } else if (format_str === "uuid") {
        return success(new UuidFormat());
      } else {
        return success(new CustomFormat(format_str));
      }
    }
  );
}
function extract_string_constraints(data) {
  let _block;
  let _pipe = run(data, at(toList(["minLength"]), int2));
  _block = from_result(_pipe);
  let min_length = _block;
  let _block$1;
  let _pipe$1 = run(
    data,
    at(toList(["maxLength"]), int2)
  );
  _block$1 = from_result(_pipe$1);
  let max_length = _block$1;
  let _block$2;
  let _pipe$2 = run(
    data,
    at(toList(["pattern"]), string2)
  );
  _block$2 = from_result(_pipe$2);
  let pattern = _block$2;
  let _block$3;
  let _pipe$3 = run(
    data,
    at(toList(["format"]), format_decoder())
  );
  _block$3 = from_result(_pipe$3);
  let format = _block$3;
  if (format instanceof None && pattern instanceof None && max_length instanceof None && min_length instanceof None) {
    return min_length;
  } else {
    return new Some(
      new StringConstraints(min_length, max_length, pattern, format)
    );
  }
}
function json_value_decoder() {
  return then$(
    dynamic,
    (dynamic_value) => {
      let $ = run(dynamic_value, string2);
      if ($ instanceof Ok) {
        let s = $[0];
        return success(new JsonString(s));
      } else {
        let $1 = run(dynamic_value, int2);
        if ($1 instanceof Ok) {
          let i = $1[0];
          return success(new JsonInteger(i));
        } else {
          let $2 = run(dynamic_value, float2);
          if ($2 instanceof Ok) {
            let f = $2[0];
            return success(new JsonNumber(f));
          } else {
            let $3 = run(dynamic_value, bool);
            if ($3 instanceof Ok) {
              let b = $3[0];
              return success(new JsonBool(b));
            } else {
              let $4 = run(dynamic_value, list2(dynamic));
              if ($4 instanceof Ok) {
                let arr = $4[0];
                let _block;
                let _pipe = arr;
                _block = filter_map(
                  _pipe,
                  (item) => {
                    let $5 = run(item, json_value_decoder());
                    if ($5 instanceof Ok) {
                      return $5;
                    } else {
                      return new Error(void 0);
                    }
                  }
                );
                let decoded_items = _block;
                return success(new JsonArray(decoded_items));
              } else {
                let $5 = run(
                  dynamic_value,
                  dict2(string2, dynamic)
                );
                if ($5 instanceof Ok) {
                  let obj = $5[0];
                  let _block;
                  let _pipe = map_to_list(obj);
                  _block = filter_map(
                    _pipe,
                    (pair) => {
                      let key;
                      let value2;
                      key = pair[0];
                      value2 = pair[1];
                      let $6 = run(value2, json_value_decoder());
                      if ($6 instanceof Ok) {
                        let decoded_value = $6[0];
                        return new Ok([key, decoded_value]);
                      } else {
                        return new Error(void 0);
                      }
                    }
                  );
                  let decoded_list = _block;
                  return success(new JsonObject(decoded_list));
                } else {
                  return success(new JsonNull());
                }
              }
            }
          }
        }
      }
    }
  );
}
function full_property_decoder() {
  return then$(
    dynamic,
    (dynamic_data) => {
      return optional_field(
        "type",
        new None(),
        optional(field_type_decoder()),
        (field_type) => {
          return optional_field(
            "title",
            new None(),
            optional(string2),
            (title) => {
              return optional_field(
                "description",
                new None(),
                optional(string2),
                (description) => {
                  return optional_field(
                    "default",
                    new None(),
                    optional(json_value_decoder()),
                    (default$) => {
                      return optional_field(
                        "enum",
                        new None(),
                        optional(list2(json_value_decoder())),
                        (enum_values) => {
                          return optional_field(
                            "items",
                            new None(),
                            optional(property_decoder()),
                            (items) => {
                              return optional_field(
                                "properties",
                                new None(),
                                optional(properties_decoder()),
                                (properties) => {
                                  return optional_field(
                                    "required",
                                    toList([]),
                                    list2(string2),
                                    (required2) => {
                                      let string_constraints = extract_string_constraints(
                                        dynamic_data
                                      );
                                      let number_constraints = extract_number_constraints(
                                        dynamic_data
                                      );
                                      return success(
                                        new SchemaProperty(
                                          field_type,
                                          title,
                                          description,
                                          default$,
                                          enum_values,
                                          string_constraints,
                                          number_constraints,
                                          items,
                                          properties,
                                          required2
                                        )
                                      );
                                    }
                                  );
                                }
                              );
                            }
                          );
                        }
                      );
                    }
                  );
                }
              );
            }
          );
        }
      );
    }
  );
}
function property_decoder() {
  return one_of(
    full_property_decoder(),
    toList([
      (() => {
        let _pipe = string2;
        return map2(
          _pipe,
          (type_str) => {
            return new SchemaProperty(
              (() => {
                if (type_str === "string") {
                  return new Some(new StringType());
                } else if (type_str === "number") {
                  return new Some(new NumberType());
                } else if (type_str === "integer") {
                  return new Some(new IntegerType());
                } else if (type_str === "boolean") {
                  return new Some(new BooleanType());
                } else if (type_str === "null") {
                  return new Some(new NullType());
                } else if (type_str === "array") {
                  return new Some(new ArrayType());
                } else if (type_str === "object") {
                  return new Some(new ObjectType());
                } else {
                  return new None();
                }
              })(),
              new None(),
              new None(),
              new None(),
              new None(),
              new None(),
              new None(),
              new None(),
              new None(),
              toList([])
            );
          }
        );
      })()
    ])
  );
}
function properties_decoder() {
  return dict2(string2, property_decoder());
}
function schema_decoder() {
  return field(
    "title",
    string2,
    (title) => {
      return optional_field(
        "description",
        new None(),
        optional(string2),
        (description) => {
          return optional_field(
            "type",
            new ObjectType(),
            field_type_decoder(),
            (field_type) => {
              return optional_field(
                "properties",
                new_map(),
                properties_decoder(),
                (properties) => {
                  return optional_field(
                    "required",
                    toList([]),
                    list2(string2),
                    (required2) => {
                      return then$(
                        dynamic,
                        (dynamic_data) => {
                          let string_constraints = extract_string_constraints(
                            dynamic_data
                          );
                          let number_constraints = extract_number_constraints(
                            dynamic_data
                          );
                          return success(
                            new JsonSchema(
                              title,
                              description,
                              field_type,
                              properties,
                              required2,
                              string_constraints,
                              number_constraints
                            )
                          );
                        }
                      );
                    }
                  );
                }
              );
            }
          );
        }
      );
    }
  );
}
function parse_schema(json_string) {
  let _pipe = json_string;
  let _pipe$1 = parse(_pipe, schema_decoder());
  return map_error(
    _pipe$1,
    (error) => {
      if (error instanceof UnexpectedEndOfInput) {
        return new InvalidJson("Unexpected end of input");
      } else if (error instanceof UnexpectedByte) {
        let byte = error[0];
        return new InvalidJson("Unexpected byte: " + byte);
      } else if (error instanceof UnexpectedSequence) {
        let seq = error[0];
        return new InvalidJson("Unexpected sequence: " + seq);
      } else {
        let errors = error[0];
        return new DecodingError(errors);
      }
    }
  );
}

// build/dev/javascript/formosh/formosh.mjs
var FormApp = class extends CustomType {
  constructor(init2, update3, view3) {
    super();
    this.init = init2;
    this.update = update3;
    this.view = view3;
  }
};
function create_form(schema) {
  return new FormApp(
    (_) => {
      return [init(schema), none()];
    },
    update2,
    view2
  );
}
function from_schema(schema) {
  return create_form(schema);
}
function to_lustre_app(form_app) {
  return application(form_app.init, form_app.update, form_app.view);
}
var example_schema = '\n{\n    "$schema": "https://json-schema.org/draft/2020-12/schema",\n    "$id": "https://example.com/lesion-measurement.schema.json",\n    "title": "\u0418\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u0435 \u043E\u0431\u0440\u0430\u0437\u043E\u0432\u0430\u043D\u0438\u0439",\n    "description": "\u0423\u043A\u0430\u0436\u0438\u0442\u0435 \u043D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0438\u0439 \u0440\u0430\u0437\u043C\u0435\u0440 \u043A\u0430\u0436\u0434\u043E\u0433\u043E \u043E\u0431\u043D\u0430\u0440\u0443\u0436\u0435\u043D\u043D\u043E\u0433\u043E \u043E\u0431\u0440\u0430\u0437\u043E\u0432\u0430\u043D\u0438\u044F \u0432 \u043C\u0438\u043B\u043B\u0438\u043C\u0435\u0442\u0440\u0430\u0445",\n    "type": "object",\n    "properties": {\n      "diagnosis": {\n        "description": "\u0414\u0438\u0430\u0433\u043D\u043E\u0437",\n        "type": "string",\n        "maxLength": 50\n      },\n      "weight": {\n        "description": "\u0412\u0435\u0441",\n        "type": "number"\n      },\n      "age": {\n        "description": "\u0412\u043E\u0437\u0440\u0430\u0441\u0442",\n        "type": "integer"\n      },\n      "diagnosis2": {\n        "description": "\u0414\u0438\u0430\u0433\u043D\u043E\u04373",\n        "type": "string",\n        "maxLength": 200\n      },\n      "lesions": {\n        "description": "\u0421\u043F\u0438\u0441\u043E\u043A \u0438\u0437\u043C\u0435\u0440\u0435\u043D\u0438\u0439 \u043E\u0431\u0440\u0430\u0437\u043E\u0432\u0430\u043D\u0438\u0439",\n        "type": "array",\n        "items": {\n          "type": "object",\n          "properties": {\n            "side": {\n              "description": "\u0421\u0442\u043E\u0440\u043E\u043D\u0430 (L - \u043B\u0435\u0432\u0430\u044F, R - \u043F\u0440\u0430\u0432\u0430\u044F)",\n              "type": "string",\n              "enum": ["L", "R"]\n            },\n            "max_size_mm": {\n              "description": "\u041D\u0430\u0438\u0431\u043E\u043B\u044C\u0448\u0438\u0439 \u0440\u0430\u0437\u043C\u0435\u0440 \u0432 \u043C\u0438\u043B\u043B\u0438\u043C\u0435\u0442\u0440\u0430\u0445",\n              "type": "number",\n              "minimum": 0,\n              "maximum": 200\n            },\n            "location": {\n              "description": "\u041B\u043E\u043A\u0430\u043B\u0438\u0437\u0430\u0446\u0438\u044F \u043E\u0431\u0440\u0430\u0437\u043E\u0432\u0430\u043D\u0438\u044F",\n              "type": "string",\n              "maxLength": 100\n            },\n            "notes": {\n              "description": "\u0414\u043E\u043F\u043E\u043B\u043D\u0438\u0442\u0435\u043B\u044C\u043D\u044B\u0435 \u043F\u0440\u0438\u043C\u0435\u0447\u0430\u043D\u0438\u044F",\n              "type": "string",\n              "maxLength": 500\n            }\n          },\n          "required": ["side", "max_size_mm"]\n        },\n        "minItems": 1\n      }\n    },\n    "required": ["lesions"]\n  }\n';
function main() {
  let _block;
  let $ = parse_schema(example_schema);
  if ($ instanceof Ok) {
    let schema = $[0];
    console_log("Successfully parsed JSON schema: " + schema.title);
    _block = new Ok(from_schema(schema));
  } else {
    let err = $[0];
    console_log("Failed to parse JSON schema");
    if (err instanceof InvalidJson) {
      let msg = err[0];
      console_log("Invalid JSON: " + msg);
    } else if (err instanceof MissingField) {
      let field2 = err[0];
      console_log("Missing field: " + field2);
    } else if (err instanceof InvalidType) {
      let msg = err[0];
      console_log("Invalid type: " + msg);
    } else if (err instanceof UnexpectedValue) {
      let msg = err[0];
      console_log("Unexpected value: " + msg);
    } else {
      console_log("JSON decoding error");
    }
    _block = new Error(err);
  }
  let form_result = _block;
  if (form_result instanceof Ok) {
    let form2 = form_result[0];
    let app = to_lustre_app(form2);
    let $1 = start3(app, "#app", void 0);
    if ($1 instanceof Ok) {
      return void 0;
    } else {
      return void 0;
    }
  } else {
    return void 0;
  }
}

// build/.lustre/entry.mjs
main();
