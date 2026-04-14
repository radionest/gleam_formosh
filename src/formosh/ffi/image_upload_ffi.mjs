export function openFilePicker(accept, maxFileSize, uploadUrl, onStarted, onUploaded, onError) {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = accept;
  input.onchange = (e) => {
    const file = e.target.files[0];
    if (!file) return;

    if (maxFileSize > 0 && file.size > maxFileSize) {
      const tempId = crypto.randomUUID();
      onError(tempId, `File too large: ${(file.size / 1048576).toFixed(1)}MB (max ${(maxFileSize / 1048576).toFixed(1)}MB)`);
      return;
    }

    const tempId = crypto.randomUUID();
    const previewUrl = URL.createObjectURL(file);
    onStarted(tempId, previewUrl);

    const formData = new FormData();
    formData.append("file", file);

    fetch(uploadUrl, {
      method: "POST",
      body: formData,
      credentials: "include",
    })
      .then((r) => {
        if (!r.ok) throw new Error(`Upload failed: ${r.status}`);
        return r.json();
      })
      .then((data) => {
        if (!data.url) throw new Error("Server response missing 'url' field");
        onUploaded(tempId, data.url);
      })
      .catch((err) => onError(tempId, err.message));
  };
  input.click();
}

export function deleteFile(uploadBaseUrl, filename) {
  fetch(`${uploadBaseUrl}/${filename}`, {
    method: "DELETE",
    credentials: "include",
  }).catch((err) => console.error("formosh: delete failed:", err));
}

export function revokeObjectUrl(url) {
  URL.revokeObjectURL(url);
}
