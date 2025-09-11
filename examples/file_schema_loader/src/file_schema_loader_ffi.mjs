// FFI module for fetching JSON files in the browser

export function fetchJson(url, callback) {
  fetch(url)
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      return response.text();
    })
    .then(text => {
      callback({ Ok: text });
    })
    .catch(error => {
      callback({ Error: error.message });
    });
}