---
title: Network fees
description: What a USDT transfer costs in {{appName}}, who the fee goes to, and why you need TRX to send.
---

Sending USDT on TRON costs a network fee. This page explains what it is and how the app works it out.

## What we charge

Nothing. During the launch period {{company}} takes no fee and no commission on transfers, and the app is free. The whole network fee goes to the TRON network, not to us. If we ever introduce a fee of our own, we will announce it on this site and in the app before it applies.

## What the network charges

A USDT (TRC-20) transfer uses two network resources:

- **Energy**, for running the USDT contract that moves the tokens. This is almost all of the cost.
- **Bandwidth**, for the size of the transaction itself.

A wallet with no staked energy pays for the energy by burning TRX. Bandwidth is free while the daily allowance that every activated TRON account gets, or bandwidth from staked TRX, covers the whole transaction. Otherwise it is paid in TRX too.

For a wallet with nothing staked, one USDT transfer currently costs about **{{networkFee}}**.

## Why the fee is paid in TRX

TRX is the TRON network's own coin, and the network charges for its resources in TRX. The fee comes out of your TRX balance, never out of the USDT you send, so the recipient gets the full amount.

So you need some TRX in the same wallet before you can send USDT. Your TRX address is the same as your USDT address.

## Why a first transfer costs more

Sending to an address that holds no USDT yet costs about twice as much as sending to one that does. The network has to create a balance record for that address.

| Recipient | Cost |
|---|---|
| Already holds USDT | The low end of {{networkFee}} |
| Holds no USDT yet | The high end of {{networkFee}} |

The app tells you when a transfer is in the dearer case.

## How the app estimates the fee

Once you enter a recipient address, the app asks the network to do a dry run of your transfer. Nothing is sent. The estimate depends on:

- **the recipient**: whether the address already holds USDT;
- **your wallet's resources**: any staked energy or bandwidth, and what is left of your free daily bandwidth;
- **the network's current prices** for energy and bandwidth, which the app reads from the network and refreshes every few hours.

The amount you send makes hardly any difference.

The review screen shows the estimate before you confirm. The energy a transfer uses can move slightly between the dry run and the real transfer. If the network does not answer the dry run, the app shows a ceiling ("up to") instead.

## If you have too little TRX

The app checks your TRX balance before you can review a transfer. You need to hold the full cost of the transfer plus a margin of 0.25 TRX. Free bandwidth and staked energy are not counted here, because they may be gone by the time the transfer is processed.

If your balance is too low, the app shows how much the transfer needs and how much you have. Add TRX to your wallet address on the TRON network and try again. The home screen also shows when your TRX is running low.

## Receiving

Receiving USDT or TRX costs you nothing. The sender pays the fee.

## Fees can change

The prices of energy and bandwidth are set by the TRON network, which can change them by vote. We do not control them. The app reads the current prices, so its estimate follows any change.

## Failed transfers

If the app or the network refuses a transfer before it is processed, nothing is sent and no fee is taken. The app tells you so.

A transfer that the network processes but that then fails, for example because it runs out of energy, still burns TRX. The app sets a limit of 100 TRX on what a single transfer can consume, well above the usual cost.

For help, see [support](/support/). For the wider risks, see the [risk disclosure](/risks/).
