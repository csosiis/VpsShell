// 国内DNS服务器
const domesticNameservers = [
  "https://dns.alidns.com/dns-query", // 阿里云公共DNS
  "https://doh.pub/dns-query", // 腾讯DNSPod
];
// 国外DNS服务器
const foreignNameservers = [
  "https://1.1.1.1/dns-query", // Cloudflare(主)
  "https://1.0.0.1/dns-query", // Cloudflare(备)
  "https://208.67.222.222/dns-query", // OpenDNS(主)
  "https://208.67.220.220/dns-query", // OpenDNS(备)
  "https://194.242.2.2/dns-query", // Mullvad(主)
  "https://194.242.2.3/dns-query" // Mullvad(备)
];
// DNS配置
const dnsConfig = {
  "enable": true,
  "listen": "0.0.0.0:1053",
  "ipv6": true,
  "use-system-hosts": false,
  "cache-algorithm": "arc",
  "enhanced-mode": "fake-ip",
  "fake-ip-range": "198.18.0.1/16",
  "fake-ip-filter": [
    // 本地主机/设备
    "+.lan",
    "+.local",
    // QQ快速登录检测失败
    "localhost.ptlogin2.qq.com",
    "localhost.sec.qq.com",
    // 微信快速登录检测失败
    "localhost.work.weixin.qq.com"
  ],
  "default-nameserver": ["223.5.5.5", "119.29.29.29", "1.1.1.1", "8.8.8.8"],
  "nameserver": [...domesticNameservers, ...foreignNameservers],
  "proxy-server-nameserver": [...domesticNameservers, ...foreignNameservers],
  "nameserver-policy": {
    "geosite:private,cn,geolocation-cn": domesticNameservers,
    "geosite:google,youtube,telegram,gfw,geolocation-!cn": foreignNameservers
  }
};
// 规则集通用配置
const ruleProviderCommon = {
  "type": "http",
  "format": "yaml",
  "interval": 86400
};
// 规则集配置
const ruleProviders = {
   "netflix": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Netflix/Netflix.yaml",
    "path": "./ruleset/loyalsoldier/netflix.yaml"
  },
  "reject": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt",
    "path": "./ruleset/loyalsoldier/reject.yaml"
  },
  "direct": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Direct/Direct.yaml",
    "path": "./ruleset/loyalsoldier/direct.yaml"
  },
  "proxy": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/proxy.txt",
    "path": "./ruleset/loyalsoldier/proxy.yaml"
  },
  "private": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/PrivateTracker/PrivateTracker.yaml",
    "path": "./ruleset/loyalsoldier/private.yaml"
  },
  "gfw": {
    ...ruleProviderCommon,
    "behavior": "domain",
    "url": "https://fastly.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/gfw.txt",
    "path": "./ruleset/loyalsoldier/gfw.yaml"
  }
};
// 规则
const rules = [
  //自定义规则
  "GEOSITE,openai,ChatGPT",
  "GEOSITE,youtube,YouTube",
  "DOMAIN-KEYWORD,gemini,Gemini",
  "GEOSITE,google,GoogleService",
  "GEOSITE,github,GitHub",
  "GEOSITE,oracle,Oracle",
  "GEOSITE,amazon,Amazon",
  "GEOSITE,telegram,Telegram",
  "PROCESS-NAME,Telegram,Telegram",
  "PROCESS-NAME,FinalShell,iTerm2",
  "PROCESS-NAME,ssh,iTerm2",
  "PROCESS-NAME,Termius,iTerm2",
  "DOMAIN-KEYWORD,hax,Hax",
  "DOMAIN-KEYWORD,chinaz,Hax",
  "GEOSITE,cloudflare,Cloudflare",
  "GEOSITE,speedtest,Speedtest",
  "PROCESS-NAME,Speedtest,Speedtest",
  "GEOSITE,netflix,Netflix",
  "GEOSITE,disney,Netflix",
  "GEOSITE,twitter,Twitter",
  "GEOSITE,tiktok,TikTok",
  "GEOSITE,spotify,Spotify",
  "GEOSITE,xiaohongshu,Twitter",
  "GEOSITE,sina,Twitter",
  "GEOSITE,douban,Twitter",
  "GEOSITE,facebook,Twitter",
  "GEOSITE,instagram,Twitter",
  "GEOSITE,category-ads-all,AdBlack",
  //规则集
  "RULE-SET,netflix,Netflix",
  "RULE-SET,direct,DIRECT",
  "RULE-SET,private,DIRECT",
  "RULE-SET,proxy,Selector",
  "RULE-SET,gfw,Selector",
  "RULE-SET,reject,AdBlack",
  //其它
  "IP-ASN,62014,Selector",
  "IP-ASN,59930,Selector",
  "IP-ASN,44907,Selector",
  "IP-ASN,211157,Selector",
  "DOMAIN-SUFFIX,tapbots.com,Selector",
  "GEOSITE,microsoft@cn,DIRECT",
  "GEOSITE,microsoft,DIRECT",
  "IP-CIDR,162.159.193.0/24,DIRECT",
  "GEOIP,LAN,DIRECT",
  "GEOIP,CN,DIRECT",
  "MATCH,Final"
];
// 代理组通用配置
const groupBaseOption = {
  "interval": 300,
  "timeout": 3000,
  "url": "https://www.google.com/generate_204",
  "lazy": true,
  "max-failed-times": 3,
  "hidden": false
};

// 程序入口
function main(config) {
  const proxyCount = config?.proxies?.length ?? 0;
  const proxyProviderCount =
    typeof config?.["proxy-providers"] === "object" ? Object.keys(config["proxy-providers"]).length : 0;
  if (proxyCount === 0 && proxyProviderCount === 0) {
    throw new Error("配置文件中未找到任何代理");
  }

  // 覆盖原配置中DNS配置
  config["dns"] = dnsConfig;

  // 覆盖原配置中的代理组
  config["proxy-groups"] = [
    {
      ...groupBaseOption,
      "name": "Selector",
      "type": "select",
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/Koolson/Qure/master/IconSet/Color/Puzzle.png"
    },
    {
      ...groupBaseOption,
      "name": "Final",
      "type": "select",
      "proxies": ["REJECT", "DIRECT","Selector"],
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/Koolson/Qure/master/IconSet/Color/Final.png"
    },
    {
      ...groupBaseOption,
      "name": "Gemini",
      "type": "select",
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/icons/gemini-ai.png"
    },
    {
      ...groupBaseOption,
      "name": "ChatGPT",
      "type": "select",
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/icons/ChatGPT.png"
    },
    {
      ...groupBaseOption,
      "name": "GoogleService",
      "type": "select",
      "include-all": true,
      "icon": "https://fastly.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/Google_Search.png"
    },
    {
      ...groupBaseOption,
      "name": "Telegram",
      "type": "select",
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/Koolson/Qure/master/IconSet/Color/Telegram.png"
    },
    {
      ...groupBaseOption,
      "name": "YouTube",
      "type": "select",
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/icons/You-tube.png"
    },
    {
      ...groupBaseOption,
      "name": "GitHub",
      "type": "select",
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/icons/git-hub.png"
    },
    {
      ...groupBaseOption,
      "name": "Oracle",
      "type": "select",
      "include-all": true,
      "proxies": ["REJECT", "DIRECT","Selector"],
      "icon": "https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/icons/oracle.png"
    },
    {
      ...groupBaseOption,
      "name": "Amazon",
      "type": "select",
      "include-all": true,
      "proxies": ["DIRECT","Selector"],
      "icon": "https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/icons/amazon.png"
    },
    {
      ...groupBaseOption,
      "name": "Hax",
      "type": "select",
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/icons/H.png"
    },
    {
      ...groupBaseOption,
      "name": "iTerm2",
      "type": "select",
      "include-all": true,
      "proxies": ["REJECT", "DIRECT","Selector"],
      "icon": "https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/icons/iTerm.png"
    },
    {
      ...groupBaseOption,
      "name": "Speedtest",
      "type": "select",
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/Koolson/Qure/master/IconSet/Color/Speedtest.png"
    },
    {
      ...groupBaseOption,
      "name": "Twitter",
      "type": "select",
      "proxies": ["DIRECT"],
      "include-all": true,
      "icon": "https://fastly.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/Twitter.png"
    },
    {
      ...groupBaseOption,
      "name": "Netflix",
      "type": "select",
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/icons/Netflix2.png"
    },
    {
      ...groupBaseOption,
      "name": "Spotify",
      "type": "select",
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/Koolson/Qure/master/IconSet/Color/Spotify.png"
    },
    {
      ...groupBaseOption,
      "name": "TikTok",
      "type": "select",
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/icons/tiktok.png"
    },
    {
      ...groupBaseOption,
      "name": "Cloudflare",
      "type": "select",
      "proxies": ["DIRECT","REJECT"],
      "include-all": true,
      "icon": "https://raw.githubusercontent.com/Koolson/Qure/master/IconSet/Color/Cloudflare.png"
    },
    //  {
    //   ...groupBaseOption,
    //   "name": "Direct",
    //   "type": "select",
    //   "proxies": [ "DIRECT","REJECT","Selector"],
    //   "icon": "https://raw.githubusercontent.com/Koolson/Qure/master/IconSet/Color/Direct.png"
    // },
    {
      ...groupBaseOption,
      "name": "AdBlack",
      "type": "select",
      "proxies": ["REJECT", "DIRECT"],
      "icon": "https://raw.githubusercontent.com/Koolson/Qure/master/IconSet/Color/AdBlack.png"
    },
    {
      ...groupBaseOption,
      "name": "Global",
      "type": "select",
      "proxies": ["REJECT", "DIRECT","Selector"],
       "include-all": true,
      "icon": "https://raw.githubusercontent.com/csosiis/VpsShell/refs/heads/main/icons/global.png"
    }
  ];

  // 覆盖原配置中的规则
  config["rule-providers"] = ruleProviders;
  config["rules"] = rules;

  // 返回修改后的配置
  return config;
}
