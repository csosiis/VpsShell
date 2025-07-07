<script>
  // 禁用系统默认的小人（哪吒）动画
  window.DisableAnimatedMan = true;

  // 背景图、移动背景图、
  window.CustomBackgroundImage = "电脑端背景图链接";
  window.CustomMobileBackgroundImage = "手机端背景图链接";
  window.ShowNetTransfer = true;
  window.FixedTopServerName = true;

  // 将所有 HTTP 链接改为 HTTPS，避免混合内容警告
  const AVIF_URL = "右上角小人";

  // 在 <head> 中注入 CSS，隐藏默认小人，定义自定义小人样式
  const style = document.createElement('style');
  style.innerHTML = `
    /* 隐藏任何通过 dicebear API 加载的默认头像 */
    .transition-opacity img[src*="dicebear"] {
      display: none !important;
    }
    /* 自定义小人样式 */
    .custom-avatar {
      position: absolute !important;
      right: -40px !important;
      top: -155px !important;
      z-index: 10 !important;
      width: 160px !important;
      height: auto !important;
    }
    .header-timer{
    display: none !important;
    }
  `;
  document.head.appendChild(style);

  // 监听 DOM 变化，自动移除系统头像并插入自定义小人
  const observer = new MutationObserver(() => {
    // 抓取小人容器
    const xpath = "/html/body/div/div/main/div[2]/section[1]/div[4]/div";
    const container = document.evaluate(
      xpath, document, null,
      XPathResult.FIRST_ORDERED_NODE_TYPE, null
    ).singleNodeValue;

    if (!container) return;

    // 移除任何残留的默认头像
    container.querySelectorAll('img[src*="dicebear"]').forEach(el => el.remove());

    // 如果还没插入自定义小人，则插入
    if (!container.querySelector('img.custom-avatar')) {
      const img = document.createElement('img');
      img.src = AVIF_URL;
      img.className = 'custom-avatar';
      container.appendChild(img);
    }
  });

  // 从页面一加载就开始观察，保持一直生效
  observer.observe(document.body, {
    childList: true,
    subtree: true
  });
</script>