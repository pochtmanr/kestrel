export default {
  meta: {
    title: '{{appName}}: a self-custody USDT wallet on TRON',
    description:
      'Hold, send and receive USDT on TRON with a wallet that keeps your keys on your iPhone or iPad. No account, no sign-up, and no fee from us.',
  },
  nav: {
    features: 'What it does',
    fees: 'Fees',
    custody: 'Your keys',
    help: 'Help',
    about: 'About',
    support: 'Support',
    main: 'Main',
    menu: 'Menu',
    close: 'Close menu',
    language: 'Language',
    skip: 'Skip to content',
    soon: 'Coming soon',
  },
  hero: {
    title: 'Your USDT. Your keys.',
    body: '{{brand}} is a wallet for USDT on the TRON network. Your recovery phrase is created on your iPhone and stays there. There is no account to open and nobody holding your funds for you.',
    cta: 'Get the app',
    soon: 'Coming soon to the App Store',
    note: 'For iPhone and iPad, iOS 17 or later. English, Russian and Chinese.',
    shotAlt: 'The {{brand}} home screen: total balance, Send and Receive, recent activity.',
  },
  features: {
    title: 'A wallet that does three things well',
    items: [
      {
        title: 'Send',
        body: 'Paste an address or scan a QR code. A review screen shows the recipient, the amount and the network fee before you confirm.',
        shot: 'send',
        alt: 'The Send screen with an amount of 125.5 USDT and a keypad.',
      },
      {
        title: 'Receive',
        body: 'Show your TRON address as a QR code, or request an exact amount. The app tells you when the payment arrives.',
        shot: 'receive',
        alt: 'The Receive screen with a QR code and the wallet address.',
      },
      {
        title: 'Keep track',
        body: 'See your full USDT history with charts, totals in and out, and the fees you have paid. A widget shows your balance on the Home Screen.',
        shot: 'activity',
        alt: 'The Activity screen with a balance chart and a list of transfers.',
      },
    ],
  },
  fees: {
    title: 'We charge nothing',
    intro:
      'During the launch period {{brand}} takes no fee and no commission. The only cost of a transfer is the TRON network fee, which goes to the network and not to us.',
    slipTitle: 'Sending 100 USDT',
    rows: [
      { label: 'You send', value: '100.00 USDT' },
      { label: 'Recipient gets', value: '100.00 USDT' },
      { label: 'TRON network fee', value: '≈ {{networkFee}}', note: 'Paid in TRX from your wallet, to the TRON network' },
      { label: '{{brand}} fee', value: '0', zero: true },
    ],
    notes: [
      'Receiving is free.',
      'You need a small TRX balance to send USDT. The app warns you when it is too low.',
      'The network sets its fee and can change it. The app shows the current estimate before you confirm.',
      'If we ever introduce a fee, we will announce it here and in the app before it applies.',
    ],
    link: 'How TRON network fees work',
  },
  custody: {
    title: 'What stays on your iPhone, and what leaves it',
    intro:
      '{{brand}} is self-custody: only you hold the keys. {{company}} never sees or holds your funds, and cannot move them, freeze them or recover them.',
    staysTitle: 'Stays on your device',
    stays: [
      'Your recovery phrase and keys, in the device Keychain',
      'Your PIN, stored as a salted hash',
      'Your transfer notes and address names',
      'A cached copy of your history',
    ],
    leavesTitle: 'Leaves your device',
    leaves: [
      'Your public wallet address, sent to TronGrid to read balances and history',
      'Transfers you have signed, sent to the TRON network',
      'Requests for USDT and TRX prices, sent to CoinGecko with no wallet details',
      'Requests for the 5-year price chart, sent to Kraken with coin names only',
    ],
    neverTitle: 'What the app does not have',
    never: 'No account, no email, no phone number, no identity checks. No analytics, advertising or tracking code.',
    shotAlt: 'The lock screen asking for a 6-digit PIN.',
    link: 'Read the privacy policy',
  },
  know: {
    title: 'Before you use it',
    items: [
      { title: 'TRON only', body: 'The wallet supports USDT (TRC-20) and TRX on TRON. USDT sent on another network, such as Ethereum or BNB Chain, will be lost.' },
      { title: 'Transfers are final', body: 'Nobody can cancel or reverse a transfer on the blockchain, us included. Check the address before you send.' },
      { title: 'Your phrase is the only backup', body: 'Write the recovery phrase down and keep it offline. If you lose it and your device, the funds are gone. We cannot restore it.' },
      { title: 'USDT has an issuer', body: 'USDT is issued by Tether, not by us. Tether can freeze USDT at any address, and USDT can lose its link to the dollar.' },
      { title: 'A wallet, nothing more', body: '{{brand}} does not exchange crypto, offer cards, hold funds or give investment advice. {{company}} is not authorised or regulated by the Financial Conduct Authority.' },
    ],
    link: 'Read the full risk disclosure',
  },
  faq: {
    title: 'Questions',
    items: [
      { q: 'Do I need an account?', a: 'No. You create a wallet on your device, or restore one with a 12- or 24-word recovery phrase. We do not ask for an email, a phone number or documents.' },
      { q: 'What does it cost?', a: 'The app is free and we take no fee on transfers during the launch period. You pay the TRON network fee, currently about {{networkFee}} for a USDT transfer, in TRX.' },
      { q: 'Why do I need TRX to send USDT?', a: 'Every transfer on TRON uses network resources, which are paid for in TRX. The fee comes out of your TRX balance, never out of the USDT you send.' },
      { q: 'Can you recover my wallet if I lose my phone?', a: 'No. Only your recovery phrase can restore the wallet. We never receive it, so we cannot recover it or reset it.' },
      { q: 'I sent USDT to the wrong address. Can you get it back?', a: 'No. Transfers cannot be reversed by anyone. Only the owner of the receiving address can send the funds back.' },
      { q: 'Which coins and networks are supported?', a: 'USDT (TRC-20) and TRX on the TRON network. Nothing else.' },
      { q: 'Will support ever ask for my recovery phrase?', a: 'Never. Anyone who asks for it is trying to steal your funds, whatever they say. Our only support address is {{supportEmail}}.' },
    ],
    link: 'More questions and answers',
  },
  lost: {
    title: 'This page does not exist',
    body: 'The address may be mistyped, or the page has moved.',
    home: 'Go to the home page',
  },
  closing: {
    title: 'Twelve words. One PIN. Done.',
    body: 'Setting up takes about a minute. Have a pen and paper ready for your recovery phrase.',
  },
  footer: {
    product: 'Product',
    legal: 'Legal',
    pages: {
      privacy: 'Privacy policy',
      terms: 'Terms of use',
      risks: 'Risk disclosure',
      restricted: 'Restricted territories',
      legal: 'Legal notice',
      support: 'Support',
      security: 'Security',
      about: 'About',
      fees: 'Network fees',
      help: 'Help',
    },
    company:
      '{{appName}} is published by {{company}}, a company registered in {{registeredIn}} (company number {{companyNumber}}). Registered office: {{registeredOffice}}.',
    status:
      '{{company}} provides wallet software only. It is not a bank, exchange or custodian, and is not authorised or regulated by the Financial Conduct Authority. Cryptoassets are high-risk and you can lose all the money you put in. You are unlikely to be protected if something goes wrong.',
    marks:
      'Tether, USDT, TRON and TRX are trademarks of their respective owners. {{brand}} is not affiliated with or endorsed by them.',
    language: 'Language',
  },
  doc: {
    updated: 'Last updated: {{lastUpdated}}',
    prevails: '',
    back: 'Back to the home page',
  },
};
