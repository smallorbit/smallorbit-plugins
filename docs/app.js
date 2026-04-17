document.querySelectorAll('.copy-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    try {
      navigator.clipboard.writeText(btn.dataset.copy).then(() => {
        const orig = btn.textContent;
        btn.textContent = 'copied!';
        setTimeout(() => { btn.textContent = orig; }, 1500);
      }).catch(() => {});
    } catch (_) {}
  });
});
