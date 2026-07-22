(() => {
  'use strict';

  function bytesToBase64(bytes) {
    let binary = '';
    const chunkSize = 0x8000;
    for (let offset = 0; offset < bytes.length; offset += chunkSize) {
      const chunk = bytes.subarray(offset, Math.min(offset + chunkSize, bytes.length));
      binary += String.fromCharCode.apply(null, chunk);
    }
    return btoa(binary);
  }

  function base64ToBytes(encoded) {
    const binary = atob(encoded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  }

  function stringToUtf8Base64(value) {
    return bytesToBase64(new TextEncoder().encode(value));
  }

  window.NativeShellCodec = Object.freeze({
    bytesToBase64,
    base64ToBytes,
    stringToUtf8Base64
  });
})();
