export default {
  meta: {
    title: '{{appName}}：TRON 网络上的自托管 USDT 钱包',
    description:
      '在 TRON 网络上持有、发送和接收 USDT。密钥只保存在你的 iPhone 或 iPad 上。无需账户，无需注册，我们不收取任何费用。',
  },
  nav: {
    features: '功能',
    fees: '费用',
    custody: '你的密钥',
    help: '帮助',
    about: '关于',
    support: '支持',
    main: '主导航',
    menu: '菜单',
    close: '关闭菜单',
    language: '语言',
    skip: '跳到正文',
    soon: '即将上架',
  },
  hero: {
    title: '你的 USDT，你的密钥。',
    body: '{{brand}} 是一款用于 TRON 网络 USDT 的钱包。助记词在你的 iPhone 上生成，并且只保存在那里。无需开设账户，也没有任何人替你保管资金。',
    cta: '获取应用',
    soon: '即将在 App Store 上架',
    note: '适用于 iPhone 和 iPad，需要 iOS 17 或更高版本。支持英文、俄文和中文。',
    shotAlt: '{{brand}} 主屏幕：总余额、发送与接收、最近的交易。',
  },
  features: {
    title: '一款把三件事做好的钱包',
    items: [
      {
        title: '发送',
        body: '粘贴地址或扫描二维码。确认之前，你会看到收款人、金额和网络费用。',
        shot: 'send',
        alt: '发送界面：金额 125.5 USDT 和数字键盘。',
      },
      {
        title: '接收',
        body: '以二维码展示你的 TRON 地址，或请求一个确切的金额。款项到账时，应用会提醒你。',
        shot: 'receive',
        alt: '接收界面：二维码和钱包地址。',
      },
      {
        title: '记录',
        body: '查看完整的 USDT 交易记录，包括图表、收支合计和已支付的费用。小组件可在主屏幕上显示余额。',
        shot: 'activity',
        alt: '交易记录界面：余额图表和转账列表。',
      },
    ],
  },
  fees: {
    title: '我们不收取任何费用',
    intro:
      '在上线初期，{{brand}} 不收取任何费用或佣金。转账的唯一成本是 TRON 网络费用，这笔费用付给网络，而不是付给我们。',
    slipTitle: '发送 100 USDT',
    rows: [
      { label: '你发送', value: '100.00 USDT' },
      { label: '收款人收到', value: '100.00 USDT' },
      { label: 'TRON 网络费用', value: '≈ {{networkFee}}', note: '从你的钱包以 TRX 支付给 TRON 网络' },
      { label: '{{brand}} 费用', value: '0', zero: true },
    ],
    notes: [
      '接收免费。',
      '发送 USDT 需要少量 TRX 余额。余额不足时，应用会提醒你。',
      '费用由网络决定，并且可能变动。确认之前，应用会显示当前的估算值。',
      '如果我们将来开始收费，会在生效之前在本网站和应用内提前公告。',
    ],
    link: 'TRON 网络费用是如何计算的',
  },
  custody: {
    title: '哪些留在你的 iPhone 上，哪些会离开',
    intro:
      '{{brand}} 是自托管钱包：密钥只在你手中。{{company}} 看不到也不持有你的资金，无法转移、冻结或找回它们。',
    staysTitle: '留在设备上',
    stays: [
      '助记词和密钥，保存在设备的钥匙串中',
      'PIN 码，以加盐哈希的形式保存',
      '你的转账备注和地址名称',
      '交易记录的本地缓存',
    ],
    leavesTitle: '离开设备',
    leaves: [
      '你的公开钱包地址：发送给 TronGrid，用于读取余额和交易记录',
      '你已签名的转账：发送到 TRON 网络',
      'USDT 和 TRX 的价格请求：发送给 CoinGecko，不含任何钱包信息',
      '5 年价格走势图的请求：发送给 Kraken，仅包含币种名称',
    ],
    neverTitle: '应用里没有的东西',
    never: '没有账户、电子邮箱、手机号码或身份验证。没有分析、广告或跟踪代码。',
    shotAlt: '锁定界面，要求输入 6 位 PIN 码。',
    link: '阅读隐私政策',
  },
  know: {
    title: '使用之前',
    items: [
      { title: '仅支持 TRON', body: '钱包支持 TRON 网络上的 USDT（TRC-20）和 TRX。通过其他网络（例如 Ethereum 或 BNB Chain）发送的 USDT 将会丢失。' },
      { title: '转账不可撤销', body: '区块链上的转账任何人都无法取消或撤回，我们也不例外。发送之前请核对地址。' },
      { title: '助记词是唯一的备份', body: '请把助记词抄写下来并离线保存。如果你同时丢失了助记词和设备，资金将无法找回。我们无法恢复它。' },
      { title: 'USDT 有发行方', body: 'USDT 由 Tether 发行，而不是由我们发行。Tether 可以冻结任何地址上的 USDT，USDT 也可能与美元脱钩。' },
      { title: '只是一个钱包', body: '{{brand}} 不兑换加密货币，不提供银行卡，不保管资金，也不提供投资建议。{{company}} 未获得英国金融行为监管局（FCA）的授权，也不受其监管。' },
    ],
    link: '阅读完整的风险披露',
  },
  faq: {
    title: '常见问题',
    items: [
      { q: '需要注册账户吗？', a: '不需要。你可以在设备上创建钱包，或者用 12 个或 24 个单词的助记词恢复钱包。我们不会索取邮箱、手机号码或证件。' },
      { q: '费用是多少？', a: '应用免费，在上线初期我们不对转账收取任何费用。你需要支付 TRON 网络费用，目前一笔 USDT 转账约为 {{networkFee}}，以 TRX 支付。' },
      { q: '为什么发送 USDT 需要 TRX？', a: 'TRON 上的每笔转账都会消耗网络资源，这些资源以 TRX 支付。费用从你的 TRX 余额中扣除，不会从你发送的 USDT 中扣除。' },
      { q: '如果我丢了手机，你们能恢复我的钱包吗？', a: '不能。只有助记词可以恢复钱包。我们从未收到过它，因此无法恢复或重置。' },
      { q: '我把 USDT 发到了错误的地址，能追回吗？', a: '不能。任何人都无法撤销转账。只有收款地址的所有者可以把资金退回。' },
      { q: '支持哪些币种和网络？', a: 'TRON 网络上的 USDT（TRC-20）和 TRX。仅此而已。' },
      { q: '客服会索要我的助记词吗？', a: '绝对不会。无论对方怎么说，索要助记词的人都是想盗取你的资金。我们唯一的支持邮箱是 {{supportEmail}}。' },
    ],
    link: '更多问题与解答',
  },
  lost: {
    title: '页面不存在',
    body: '地址可能输入有误，或者页面已被移动。',
    home: '返回首页',
  },
  closing: {
    title: '十二个单词，一个 PIN 码，完成。',
    body: '设置大约需要一分钟。请准备好纸和笔，用来抄写助记词。',
  },
  footer: {
    product: '产品',
    legal: '法律文件',
    pages: {
      privacy: '隐私政策',
      terms: '使用条款',
      risks: '风险披露',
      restricted: '受限地区',
      legal: '法律声明',
      support: '支持',
      security: '安全',
      about: '关于',
      fees: '网络费用',
      help: '帮助',
    },
    company:
      '{{appName}} 由 {{company}} 发布。该公司在英格兰和威尔士注册（公司编号 {{companyNumber}}）。注册办公地址：{{registeredOffice}}。',
    status:
      '{{company}} 仅提供钱包软件。它不是银行、交易所或托管机构，未获得 FCA 的授权，也不受其监管。加密资产风险很高，你可能损失投入的全部资金，并且在出现问题时很可能得不到保护。本服务不面向中国大陆居民提供。',
    marks:
      'Tether、USDT、TRON 和 TRX 是其各自所有者的商标。{{brand}} 与它们没有关联，也未获得其认可。',
    language: '语言',
  },
  doc: {
    updated: '最后更新：{{lastUpdated}}',
    prevails: '本文为译文。如有不一致之处，以英文版本为准。',
    back: '返回首页',
  },
};
