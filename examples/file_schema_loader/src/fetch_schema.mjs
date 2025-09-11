export function fetchSchema(url, callback) {
  console.log("JS FFI "+url)
  fetch(url)
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      return response.text();
    })
    .then(text => {
      callback(text);
    })
    .catch(error => {
      callback(new Error(error.message));
    });
}