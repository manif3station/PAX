async function ping() {
  const node = document.getElementById('result');
  const response = await fetch('/healthz');
  const payload = await response.json();
  node.textContent = JSON.stringify(payload, null, 2);
}

document.getElementById('ping').addEventListener('click', () => {
  ping().catch((error) => {
    document.getElementById('result').textContent = String(error);
  });
});
