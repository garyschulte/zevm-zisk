const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");

/// Ethereum block header - follows alloy-consensus Header structure
pub const Header = struct {
    /// Parent block hash
    parent_hash: primitives.Hash,

    /// Ommers/uncles hash
    ommers_hash: primitives.Hash,

    /// Block beneficiary (coinbase/miner)
    beneficiary: primitives.Address,

    /// State root hash
    state_root: primitives.Hash,

    /// Transactions trie root
    transactions_root: primitives.Hash,

    /// Receipts trie root
    receipts_root: primitives.Hash,

    /// Logs bloom filter (256 bytes)
    logs_bloom: [256]u8,

    /// Block difficulty (pre-Merge)
    difficulty: primitives.U256,

    /// Block number
    number: u64,

    /// Gas limit for this block
    gas_limit: u64,

    /// Gas used by all transactions
    gas_used: u64,

    /// Block timestamp (seconds since UNIX epoch)
    timestamp: u64,

    /// Extra data (up to 32 bytes typically)
    extra_data: []const u8,

    /// Mix hash (pre-Merge) / prevrandao (post-Merge)
    mix_hash: primitives.Hash,

    /// Nonce (8 bytes, pre-Merge only)
    nonce: u64,

    // EIP-1559 (London)
    /// Base fee per gas
    base_fee_per_gas: ?u64,

    // EIP-4895 (Shanghai)
    /// Withdrawals root hash
    withdrawals_root: ?primitives.Hash,

    // EIP-4844 (Cancun)
    /// Total blob gas used in block
    blob_gas_used: ?u64,

    /// Excess blob gas from previous blocks
    excess_blob_gas: ?u64,

    // EIP-4788 (Cancun)
    /// Parent beacon block root
    parent_beacon_block_root: ?primitives.Hash,

    // EIP-7685 (Prague)
    /// Requests hash
    requests_hash: ?primitives.Hash,

    pub fn init(allocator: std.mem.Allocator) !Header {
        _ = allocator;
        return Header{
            .parent_hash = std.mem.zeroes(primitives.Hash),
            .ommers_hash = std.mem.zeroes(primitives.Hash),
            .beneficiary = std.mem.zeroes(primitives.Address),
            .state_root = std.mem.zeroes(primitives.Hash),
            .transactions_root = std.mem.zeroes(primitives.Hash),
            .receipts_root = std.mem.zeroes(primitives.Hash),
            .logs_bloom = std.mem.zeroes([256]u8),
            .difficulty = 0,
            .number = 0,
            .gas_limit = 0,
            .gas_used = 0,
            .timestamp = 0,
            .extra_data = &.{},
            .mix_hash = std.mem.zeroes(primitives.Hash),
            .nonce = 0,
            .base_fee_per_gas = null,
            .withdrawals_root = null,
            .blob_gas_used = null,
            .excess_blob_gas = null,
            .parent_beacon_block_root = null,
            .requests_hash = null,
        };
    }

    /// Convert header to BlockEnv for execution context
    pub fn toBlockEnv(self: *const Header) context.BlockEnv {
        return .{
            .number = @as(primitives.U256, self.number),
            .beneficiary = self.beneficiary,
            .timestamp = @as(primitives.U256, self.timestamp),
            .gas_limit = self.gas_limit,
            .basefee = self.base_fee_per_gas orelse 0,
            .difficulty = self.difficulty,
            .prevrandao = if (self.number >= 15537394) self.mix_hash else null, // Post-Merge block number
            // TODO: Properly construct BlobExcessGasAndPrice using .new() method from block module
            // For now, set to null (EIP-4844 blob support can be added later)
            .blob_excess_gas_and_price = null,
        };
    }
};

/// Calculate blob gas price from excess blob gas (EIP-4844)
fn calculateBlobGasPrice(excess_blob_gas: u64) u64 {
    // Simplified calculation - use fake_exponential for production
    const MIN_BLOB_GASPRICE: u64 = 1;
    if (excess_blob_gas == 0) {
        return MIN_BLOB_GASPRICE;
    }
    // For now, just return a simple calculation
    return MIN_BLOB_GASPRICE + (excess_blob_gas / 131072); // TARGET_BLOB_GAS_PER_BLOCK
}

/// Withdrawal (EIP-4895)
pub const Withdrawal = struct {
    index: u64,
    validator_index: u64,
    address: primitives.Address,
    amount: u64, // in Gwei
};

/// Simple transaction representation
/// In production, this should support all transaction types (Legacy, EIP-2930, EIP-1559, EIP-4844, EIP-7702)
pub const Transaction = struct {
    /// Transaction type (0=Legacy, 1=EIP-2930, 2=EIP-1559, 3=EIP-4844, 4=EIP-7702)
    tx_type: u8,

    /// Chain ID
    chain_id: ?u64,

    /// Transaction nonce
    nonce: u64,

    /// Gas price (or max_fee_per_gas for EIP-1559)
    gas_price: u128,

    /// Priority fee (EIP-1559 only)
    gas_priority_fee: ?u128,

    /// Gas limit
    gas_limit: u64,

    /// Transaction kind (Create or Call)
    to: ?primitives.Address, // null = Create

    /// Value being transferred
    value: primitives.U256,

    /// Call data or init code
    data: []const u8,

    /// Access list (EIP-2930)
    access_list: []const AccessListItem,

    /// Blob hashes (EIP-4844)
    blob_hashes: []const primitives.Hash,

    /// Max fee per blob gas (EIP-4844)
    max_fee_per_blob_gas: u128,

    /// Signature v
    v: u64,

    /// Signature r
    r: primitives.U256,

    /// Signature s
    s: primitives.U256,

    pub fn init(allocator: std.mem.Allocator) !Transaction {
        _ = allocator;
        return Transaction{
            .tx_type = 0,
            .chain_id = null,
            .nonce = 0,
            .gas_price = 0,
            .gas_priority_fee = null,
            .gas_limit = 0,
            .to = null,
            .value = 0,
            .data = &.{},
            .access_list = &.{},
            .blob_hashes = &.{},
            .max_fee_per_blob_gas = 0,
            .v = 0,
            .r = 0,
            .s = 0,
        };
    }

    /// Recover sender address from signature (placeholder - needs full ECDSA recovery)
    pub fn recoverSender(self: *const Transaction) !primitives.Address {
        // TODO: Implement proper ECDSA signature recovery
        // For now, return zero address
        _ = self;
        return std.mem.zeroes(primitives.Address);
    }

    /// Convert to TxEnv for execution
    pub fn toTxEnv(self: *const Transaction, allocator: std.mem.Allocator, sender: primitives.Address) !context.TxEnv {
        const kind: context.TxKind = if (self.to) |addr| .{ .Call = addr } else .Create;

        // Convert data to ArrayList
        var data_list = std.ArrayList(u8).init(allocator);
        try data_list.appendSlice(self.data);

        // Convert access list
        var access_list = context.AccessList.init(allocator);
        for (self.access_list) |item| {
            var storage_keys = std.ArrayList(primitives.U256).init(allocator);
            try storage_keys.appendSlice(item.storage_keys);
            try access_list.append(.{
                .address = item.address,
                .storage_keys = storage_keys,
            });
        }

        return context.TxEnv{
            .tx_type = self.tx_type,
            .caller = sender,
            .gas_limit = self.gas_limit,
            .gas_price = self.gas_price,
            .kind = kind,
            .value = self.value,
            .data = data_list,
            .nonce = self.nonce,
            .chain_id = self.chain_id,
            .access_list = access_list,
            .gas_priority_fee = self.gas_priority_fee,
            .blob_hashes = null, // TODO: Convert blob hashes
            .max_fee_per_blob_gas = self.max_fee_per_blob_gas,
            .authorization_list = null,
        };
    }
};

/// Access list item (EIP-2930)
pub const AccessListItem = struct {
    address: primitives.Address,
    storage_keys: []const primitives.U256,
};

/// Ethereum block - follows alloy-consensus Block structure
pub const Block = struct {
    allocator: std.mem.Allocator,

    /// Block header
    header: Header,

    /// Block transactions
    transactions: []Transaction,

    /// Ommers/uncle headers
    ommers: []Header,

    /// Withdrawals (EIP-4895)
    withdrawals: ?[]Withdrawal,

    pub fn init(allocator: std.mem.Allocator) !Block {
        return Block{
            .allocator = allocator,
            .header = try Header.init(allocator),
            .transactions = &.{},
            .ommers = &.{},
            .withdrawals = null,
        };
    }

    pub fn deinit(self: *Block) void {
        if (self.transactions.len > 0) {
            self.allocator.free(self.transactions);
        }
        if (self.ommers.len > 0) {
            self.allocator.free(self.ommers);
        }
        if (self.withdrawals) |w| {
            self.allocator.free(w);
        }
    }
};

/// Account state in the execution witness
pub const WitnessAccount = struct {
    /// Account nonce
    nonce: u64,

    /// Account balance
    balance: primitives.U256,

    /// Code hash
    code_hash: primitives.Hash,

    /// Storage slots
    storage: []const WitnessStorageSlot,

    /// Bytecode (if available)
    code: ?[]const u8,
};

/// Storage slot in witness
pub const WitnessStorageSlot = struct {
    key: primitives.U256,
    value: primitives.U256,
};

/// Execution witness - follows alloy ExecutionWitness structure
/// Contains all pre-state data needed for stateless execution
pub const ExecutionWitness = struct {
    allocator: std.mem.Allocator,

    /// Hashed trie node preimages (raw bytes)
    state: [][]const u8,

    /// Contract code preimages
    codes: [][]const u8,

    /// Unhashed account addresses and storage keys
    keys: [][]const u8,

    /// RLP-encoded block headers (for BLOCKHASH opcode)
    headers: [][]const u8,

    pub fn init(allocator: std.mem.Allocator) ExecutionWitness {
        return ExecutionWitness{
            .allocator = allocator,
            .state = &.{},
            .codes = &.{},
            .keys = &.{},
            .headers = &.{},
        };
    }

    pub fn deinit(self: *ExecutionWitness) void {
        for (self.state) |item| {
            self.allocator.free(item);
        }
        if (self.state.len > 0) {
            self.allocator.free(self.state);
        }

        for (self.codes) |item| {
            self.allocator.free(item);
        }
        if (self.codes.len > 0) {
            self.allocator.free(self.codes);
        }

        for (self.keys) |item| {
            self.allocator.free(item);
        }
        if (self.keys.len > 0) {
            self.allocator.free(self.keys);
        }

        for (self.headers) |item| {
            self.allocator.free(item);
        }
        if (self.headers.len > 0) {
            self.allocator.free(self.headers);
        }
    }
};

/// Stateless input - follows reth StatelessInput structure
/// Contains both the block to execute and the witness data needed for execution
pub const StatelessInput = struct {
    allocator: std.mem.Allocator,

    /// The block being executed
    block: Block,

    /// Execution witness with pre-state data
    witness: ExecutionWitness,

    pub fn init(allocator: std.mem.Allocator) !StatelessInput {
        return StatelessInput{
            .allocator = allocator,
            .block = try Block.init(allocator),
            .witness = ExecutionWitness.init(allocator),
        };
    }

    pub fn deinit(self: *StatelessInput) void {
        self.block.deinit();
        self.witness.deinit();
    }
};
