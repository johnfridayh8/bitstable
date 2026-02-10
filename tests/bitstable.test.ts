import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v0.14.0/index.ts';
import { assertEquals, assert } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
  name: "Full Protocol Suite: Payment Channels + BitStable + TWAF",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const wallet1 = accounts.get("wallet_1")!;
    const wallet2 = accounts.get("wallet_2")!;

    // ------------------------------
    // PAYMENT CHANNEL TESTS
    // ------------------------------

    const channelId = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

    // Create payment channel
    let block = chain.mineBlock([
      Tx.contractCall("payment-channel", "create-channel", [
        types.buff(Buffer.from(channelId, 'hex')),
        types.principal(wallet2.address),
        types.uint(1000)
      ], wallet1.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // Fund channel
    block = chain.mineBlock([
      Tx.contractCall("payment-channel", "fund-channel", [
        types.buff(Buffer.from(channelId, 'hex')),
        types.principal(wallet2.address),
        types.uint(500)
      ], wallet1.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // ------------------------------
    // BITSTABLE PROTOCOL TESTS
    // ------------------------------

    // Initialize protocol
    block = chain.mineBlock([
      Tx.contractCall("bitstable", "initialize", [types.uint(30000)], deployer.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // Create vault & deposit collateral
    block = chain.mineBlock([
      Tx.contractCall("bitstable", "create-vault", [types.uint(1000)], wallet1.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // Mint stablecoins
    block = chain.mineBlock([
      Tx.contractCall("bitstable", "mint-stablecoin", [types.uint(1000)], wallet1.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // ------------------------------
    // ORACLE & GOVERNANCE UPDATES
    // ------------------------------

    // Add oracle
    block = chain.mineBlock([
      Tx.contractCall("bitstable", "add-oracle", [types.principal(wallet2.address)], deployer.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // Update BTC price
    block = chain.mineBlock([
      Tx.contractCall("bitstable", "update-price", [types.uint(35000)], wallet2.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // Set new minimum collateral ratio
    block = chain.mineBlock([
      Tx.contractCall("bitstable", "set-minimum-collateral-ratio", [types.uint(200)], deployer.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // ------------------------------
    // EMERGENCY SHUTDOWN
    // ------------------------------

    block = chain.mineBlock([
      Tx.contractCall("bitstable", "trigger-emergency-shutdown", [], deployer.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // ------------------------------
    // LIQUIDATION TEST
    // ------------------------------

    // Add liquidator
    block = chain.mineBlock([
      Tx.contractCall("bitstable", "add-liquidator", [types.principal(wallet2.address)], deployer.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // Simulate undercollateralized vault for liquidation
    // (Use low price via oracle to trigger liquidation)
    block = chain.mineBlock([
      Tx.contractCall("bitstable", "update-price", [types.uint(1000)], wallet2.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    block = chain.mineBlock([
      Tx.contractCall("bitstable", "liquidate", [types.principal(wallet1.address)], wallet2.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // ------------------------------
    // TIME-WEIGHTED STABILITY FEE (TWAF)
    // ------------------------------

    // Recreate vault and mint for TWAF testing
    block = chain.mineBlock([
      Tx.contractCall("bitstable", "create-vault", [types.uint(1000)], wallet1.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    block = chain.mineBlock([
      Tx.contractCall("bitstable", "mint-stablecoin", [types.uint(1000)], wallet1.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // Simulate 10 blocks passage for fee accrual
    for (let i = 0; i < 10; i++) {
      chain.mineBlock([]);
    }

    // Check accrued debt including TWAF
    let result = chain.callReadOnlyFn(
      "bitstable",
      "get-vault",
      [types.principal(wallet1.address)],
      wallet1.address
    );
    const vaultBeforeRepay = result.result.expectSome();
    const debtBefore = Number(vaultBeforeRepay.value.debt);

    // Repay partial debt
    block = chain.mineBlock([
      Tx.contractCall("bitstable", "repay-debt", [types.uint(100)], wallet1.address)
    ]);
    assertEquals(block.receipts[0].result.expectOk(), true);

    // Read vault debt again
    result = chain.callReadOnlyFn(
      "bitstable",
      "get-vault",
      [types.principal(wallet1.address)],
      wallet1.address
    );
    const vaultAfter = result.result.expectSome();
    const debtAfter = Number(vaultAfter.value.debt);

    // Assert accrued stability fee
    assert(debtAfter > debtBefore - 100, "Debt should include accrued stability fee");
  },
});
