module trie::trie {
    use StarcoinFramework::Table;
    use StarcoinFramework::Table::Table;
    use StarcoinFramework::Hash::keccak_256 as keccak256;
    use StarcoinFramework::Vector;
    use StarcoinFramework::Vector::length;
    use StarcoinFramework::Option::Option;
    use StarcoinFramework::Option;
    use StarcoinFramework::Errors;

    use trie::byte_utils;
    use trie::hash_value::{HashValue};
    use trie::hash_value;
    use trie::byte_utils::{slice, slice_to_end, get_shared_length, to_nibbles};
    use trie::rlp;
    use trie::rlp_stream;
    use trie::rlp::Rlp;
    use trie::byte_utils::{from_nibbles};

    //use StarcoinFramework::Hash::keccak;
    const HASH_LENGTH: u8 = 32;

    /// Just a utility constant. RLP represents `NULL` as 0x80.
    /// rlp("") = 0x80
    const RLP_NULL_BYTES: vector<u8> = vector[0x80];

    /// The KECCAK of the RLP encoding of empty data.
    /// keccak(rlp(""))
    const KECCAK256_RLP_NULL_BYTES: vector<u8> = vector[
        0x56, 0xe8, 0x1f, 0x17, 0x1b, 0xcc, 0x55, 0xa6, 0xff, 0x83, 0x45, 0xe6, 0x92, 0xc0, 0xf8, 0x6e, 0x5b, 0x48, 0xe0,
        0x1b, 0x99, 0x6c, 0xad, 0xc0, 0x01, 0x62, 0x2f, 0xb5, 0xe3, 0x63, 0xb4, 0x21,
    ];


    /// The KECCAK of the RLP encoding of empty list.
    /// /// keccak(rlp(vec![]))
    const KECCAK_EMPTY_LIST_RLP: vector<u8> = vector[
        0x1d, 0xcc, 0x4d, 0xe8, 0xde, 0xc7, 0x5d, 0x7a, 0xab, 0x85, 0xb5, 0x67, 0xb6, 0xcc, 0xd4, 0x1a, 0xd3, 0x12, 0x45,
        0x1b, 0x94, 0x8a, 0x74, 0x13, 0xf0, 0xa1, 0x42, 0xfd, 0x40, 0xd4, 0x93, 0x47,
    ];
    // /// keccak("")
    // const KECCAK_EMPTY: vector<u8> = vector[
    //     0xc5, 0xd2, 0x46, 0x01, 0x86, 0xf7, 0x23, 0x3c, 0x92, 0x7e, 0x7d, 0xb2, 0xdc, 0xc7, 0x03, 0xc0, 0xe5, 0x00, 0xb6,
    //     0x53, 0xca, 0x82, 0x27, 0x3b, 0x7b, 0xfa, 0xd8, 0x04, 0x5d, 0x85, 0xa4, 0x70,
    // ];


    const Branch_Node_Type: u8 = 0;
    const Extension_Node_Type: u8 = 1;
    const Leaf_Node_Type: u8 = 2;
    const Empty_Node_Type: u8 = 3;

    struct Node has copy, drop, key, store {
        ty: u8,
        leaf: Option<Leaf>,
        extension: Option<Extension>,
        branch: Option<Branch>,
    }

    struct Branch has copy, drop, store {
        branches: vector<Option<ChildReference>>,
        value: Option<vector<u8>>,
    }

    struct Extension has copy, drop, store {
        /// path in nibble
        partial_path: vector<u8>,
        child: ChildReference
    }

    struct Leaf has copy, drop, store {
        /// path in nibble
        partial_path: vector<u8>,
        value: vector<u8>,
    }

    /// inline or hash.
    /// if hash, data.len must be 32.
    /// if inline, data.len must < 32.
    struct ChildReference has copy, drop, store {
        inline: bool,
        data: vector<u8>,
    }

    const Invalid_Node_Type: u64 = 101;

    public fun branch_to_node(branch: Branch): Node {
        Node {
            ty: Branch_Node_Type,
            branch: Option::some(branch),
            extension: Option::none(),
            leaf: Option::none()
        }
    }

    public fun as_leaf(node: Node): Leaf {
        assert!(node.ty == Leaf_Node_Type, Invalid_Node_Type);
        Option::destroy_some(node.leaf)
    }

    public fun as_extension(node: Node): Extension {
        assert!(node.ty == Extension_Node_Type, Invalid_Node_Type);
        Option::destroy_some(node.extension)
    }

    public fun as_branch(node: Node): Branch {
        assert!(node.ty == Branch_Node_Type, Invalid_Node_Type);
        Option::destroy_some(node.branch)
    }

    public fun borrow_as_leaf(node: &Node): &Leaf {
        assert!(node.ty == Leaf_Node_Type, Invalid_Node_Type);
        Option::borrow(&node.leaf)
    }

    public fun borrow_as_extension(node: &Node): &Extension {
        assert!(node.ty == Extension_Node_Type, Invalid_Node_Type);
        Option::borrow(&node.extension)
    }

    public fun borrow_as_branch(node: &Node): &Branch {
        assert!(node.ty == Branch_Node_Type, Invalid_Node_Type);
        Option::borrow(&node.branch)
    }

    public fun borrow_mut_as_leaf(node: &mut Node): &mut Leaf {
        assert!(node.ty == Leaf_Node_Type, Invalid_Node_Type);
        Option::borrow_mut(&mut node.leaf)
    }

    public fun borrow_mut_as_extension(node: &mut Node): &mut Extension {
        assert!(node.ty == Extension_Node_Type, Invalid_Node_Type);
        Option::borrow_mut(&mut node.extension)
    }

    public fun borrow_mut_as_branch(node: &mut Node): &mut Branch {
        assert!(node.ty == Branch_Node_Type, Invalid_Node_Type);
        Option::borrow_mut(&mut node.branch)
    }

    /// path is in nibble
    public fun make_leaf_node(partial_path: vector<u8>, value: vector<u8>): Node {
        Node {
            ty: Leaf_Node_Type,
            leaf: Option::some(Leaf {
                partial_path,
                value
            }),
            extension: Option::none(),
            branch: Option::none()
        }
    }

    public fun make_extension_node(partial_path: vector<u8>, key: ChildReference): Node {
        Node {
            ty: Extension_Node_Type,
            extension: Option::some(Extension {
                partial_path,
                child: key
            }),
            leaf: Option::none(),
            branch: Option::none()
        }
    }

    public fun make_branch_node(branches: vector<Option<ChildReference>>, value: Option<vector<u8>>): Node {
        Node {
            ty: Branch_Node_Type,
            branch: Option::some(Branch {
                branches,
                value
            }),
            leaf: Option::none(),
            extension: Option::none(),
        }
    }

    public fun make_empty_branch_node(): Branch {
        let branch = Branch {
            branches: Vector::empty(),
            value: Option::none()
        };
        let i = 0;

        while (i < 16) {
            Vector::push_back(&mut branch.branches, Option::none());
            i = i + 1;
        };
        branch
    }


    /// node must be a leaf or extension.
    public fun get_node_partial_path(node: &Node): &vector<u8> {
        if (node.ty == Leaf_Node_Type) {
            &borrow_as_leaf(node).partial_path
        } else if (node.ty == Extension_Node_Type) {
            &borrow_as_extension(node).partial_path
        } else {
            abort Invalid_Node_Type
        }
    }

    public fun get_node_value(node: &Node): &vector<u8> {
        if (node.ty == Leaf_Node_Type) {
            &borrow_as_leaf(node).value
        } else if (node.ty == Extension_Node_Type) {
            &borrow_as_extension(node).child.data
        } else {
            abort Invalid_Node_Type
        }
    }
    const WrongNodeLen: u64 = 200;
    public fun from_rlp_elems(elems: &vector<Rlp>): Node {
        let elem_len = length(elems);
        assert!(elem_len == 2 || elem_len == 17, Errors::invalid_argument(WrongNodeLen));
        if (length(elems) == 2) {
            let (leaf, partial_path) = decode_to_partial_path(&rlp::as_val(Vector::borrow(elems, 0)));
            if (leaf) {
                make_leaf_node(partial_path, rlp::as_val(Vector::borrow(elems, 1)))
            } else {
                make_extension_node(partial_path, decode_child_reference(Vector::borrow(elems, 1)))
            }
        } else {
            let branches = Vector::empty();
            let i = 0;
            while (i < 16) {
                let elem = Vector::borrow(elems, i);
                Vector::push_back(&mut branches, decode_optional_child_reference(elem));
                i = i + 1;
            };
            make_branch_node(branches, decode_optional_value(Vector::borrow(elems, 16)))
        }
    }


    public fun rlp_decode(node_data: &vector<u8>): Node {
        let rlp = rlp::new(*node_data);
        let elems = rlp::as_list(&rlp);
        from_rlp_elems(&elems)
    }

    public fun rlp_encode(node: &Node): vector<u8> {
        if (node.ty == Leaf_Node_Type) {
            let node = Option::borrow(&node.leaf);
            let encoder = rlp_stream::new_list(2);
            rlp_stream::append(&mut encoder, encode_partial_path(node.partial_path, true));
            rlp_stream::append(&mut encoder, node.value);
            rlp_stream::out(encoder)
        } else if (node.ty == Extension_Node_Type) {
            let node = Option::borrow(&node.extension);
            let encoder = rlp_stream::new_list(2);
            rlp_stream::append(&mut encoder, encode_partial_path(node.partial_path, false));
            if (node.child.inline) {
                rlp_stream::append_raw(&mut encoder, node.child.data, 1);
            } else {
                rlp_stream::append(&mut encoder, node.child.data);
            };
            rlp_stream::out(encoder)
        } else if (node.ty == Branch_Node_Type) {
            let node = Option::borrow(&node.branch);
            let encoder = rlp_stream::new_list(17);
            let i = 0;
            while (i < 16) {
                let child = Vector::borrow(&node.branches, i);
                if (Option::is_none(child)) {
                    rlp_stream::append_empty_data(&mut encoder);
                } else {
                    let c = Option::borrow(child);
                    if (c.inline) {
                        rlp_stream::append_raw(&mut encoder, c.data, 1);
                    } else {
                        rlp_stream::append(&mut encoder, c.data);
                    };
                };
                i = i + 1;
            };
            let value = &node.value;
            if (Option::is_none(value)) {
                rlp_stream::append_empty_data(&mut encoder);
            } else {
                rlp_stream::append(&mut encoder, *Option::borrow(value));
            };

            rlp_stream::out(encoder)
        } else if (node.ty == Empty_Node_Type) {
            RLP_NULL_BYTES
        } else {
            abort Errors::invalid_argument(Invalid_Node_Type)
        }
    }

    fun decode_optional_value(rlp: &Rlp): Option<vector<u8>> {
        if (rlp::is_empty(rlp)) {
            Option::none()
        } else {
            Option::some(rlp::as_val(rlp))
        }
    }

    fun decode_optional_child_reference(rlp: &Rlp): Option<ChildReference> {
        if (rlp::is_empty(rlp)) {
            Option::none()
        } else {
            Option::some(decode_child_reference(rlp))
        }
    }

    fun decode_child_reference(rlp: &Rlp): ChildReference {
        if (length(&rlp::raw(rlp)) < (HASH_LENGTH as u64)) {
            ChildReference {
                inline: true,
                data: rlp::raw(rlp)
            }
        } else {
            ChildReference {
                inline: false,
                data: rlp::as_val(rlp)
            }
        }
    }

    public fun new_node_id(hash: vector<u8>): ChildReference {
        ChildReference {
            inline: length(&hash) < 32,
            data: hash
        }
    }

    public fun node_id_from_hash(hash: HashValue): ChildReference {
        ChildReference {
            inline: false,
            data: hash_value::to_bytes(hash)
        }
    }


    public fun edit_leaf_value(leaf: &mut Leaf, new_value: vector<u8>) {
        leaf.value = new_value;
    }

    /// edit a branch index, return new created branch
    public fun edit_branch_index(branch_node: &mut Branch, branch_key: u8, branch_value: ChildReference) {
        *Vector::borrow_mut(&mut branch_node.branches, (branch_key as u64)) = Option::some(branch_value);
    }

    public fun edit_branch_value(branch_node_data: &mut Branch, new_value: vector<u8>) {
        branch_node_data.value = Option::some(new_value);
    }

    public fun edit_extension_value(extension: &mut Extension, child: ChildReference) {
        extension.child = child;
    }


    /// compact encoding of hex sequence with optional terminator
    public fun encode_partial_path(path: vector<u8>, leaf: bool): vector<u8> {
        let offset = length(&path) % 2;
        let flag = (if (leaf) { 2 } else { 0 }) + (offset as u8);
        let encoded = Vector::singleton(flag);
        if (offset == 0) {
            Vector::push_back(&mut encoded, 0);
        };
        Vector::append(&mut encoded, path);
        from_nibbles(&encoded)
    }

    const WrongNodeKeyPrefix: u64 = 300;
    /// decode partial path
    /// return: (is_leaf, partial_path)

    public fun decode_to_partial_path(encoded: &vector<u8>): (bool, vector<u8>) {
        let encoded_path = byte_utils::to_nibbles(encoded);
        let prefix = *Vector::borrow(&encoded_path, 0);
        let leaf = if (prefix < 2) {
            false
        } else if (prefix < 4) {
            true
        }else {
            abort Errors::invalid_argument(WrongNodeKeyPrefix)
        };
        let offset = 2 - prefix % 2;
        (leaf, slice_to_end(&encoded_path, (offset as u64)))
    }


    struct TrieDB has key, store {
        /// hash_of_value -> value
        data: Table<HashValue, vector<u8>>,
    }

    /// create a new tridb
    public fun new(): TrieDB {
        TrieDB {
            data: Table::new()
        }
    }

    public fun save(signer: &signer, trie: TrieDB) {
        move_to(signer, trie)
    }


    /// Add encoded node data to trie db.
    /// no matter the length of it, always hash and save it,
    /// and return the hash
    public fun add_raw_node(trie: &mut TrieDB, encoded_node_data: vector<u8>): HashValue {
        let hash = hash_value::new(keccak256(encoded_node_data));
        if (!Table::contains(&trie.data, hash)) {
            Table::add(&mut trie.data, hash, encoded_node_data);
        };
        hash
    }

    /// Add/update `key`/`value` pair to a trie with `root` based on an existed triedb.
    public fun update(trie: &mut TrieDB, root: HashValue, key: vector<u8>, value: vector<u8>): HashValue {
        // Special case when inserting the very first node.
        if (hash_value::bytes(&root) == &KECCAK256_RLP_NULL_BYTES) {
            return get_single_node_root_hash(trie, key, value)
        };
        let (proof, keyRemainder, _) = walk_node_path(trie, root, &key);
        let new_root = insert_with_walk_path(trie, proof, keyRemainder, key, value);
        new_root
    }

    public fun get(trie: &TrieDB, root: HashValue, key: &vector<u8>): Option<vector<u8>> {
        let (_, _path_remainder, path_value) = walk_node_path(trie, root, key);
        // let exists = (length(&path_remainder) == 0);

        // // provided proof is not valid.
        // assert!(
        //     (exists && Option::is_some(&path_value)) || (!exists && Option::is_none(&path_value)), 1000);
        path_value
    }

    fun walk_node_path(trie: &TrieDB, root: HashValue, key: &vector<u8>): (vector<Node>, vector<u8>, Option<vector<u8>>) {
        let nibble_path = byte_utils::to_nibbles(key);
        walk_node_path_inner(trie, node_id_from_hash(root), &nibble_path, 0, Vector::empty())
    }


    fun walk_node_path_inner(trie: &TrieDB, node_id: ChildReference, path_in_nibble: &vector<u8>, path_index: u64, proof: vector<Node>): (vector<Node>, vector<u8>, Option<vector<u8>>) {
        let current_node = get_trie_node(trie, node_id);
        Vector::push_back(&mut proof, current_node);
        if (current_node.ty == Branch_Node_Type) {
            // branch node
            let current_node = borrow_as_branch(&current_node);
            if (path_index == length(path_in_nibble)) {
                // We've hit the end of the key
                // meaning the value should be within this branch node, or is empty
                (proof, Vector::empty<u8>(), current_node.value)
            } else {
                // We're not at the end of the key yet.
                // Figure out what the next node ID should be and continue.
                let branch_key = *Vector::borrow(path_in_nibble, path_index);
                let next_node_id = Vector::borrow(&current_node.branches, (branch_key as u64));
                if (Option::is_none(next_node_id)) {
                    (proof, slice_to_end(path_in_nibble, path_index), Option::none())
                } else {
                    let next_node_id = *Option::borrow(next_node_id);
                    walk_node_path_inner(trie, next_node_id, path_in_nibble, path_index + 1, (move proof))
                }
            }
        } else if (current_node.ty == Extension_Node_Type) {
            // extension node
            let current_node = borrow_as_extension(&current_node);
            let node_partial_path = &current_node.partial_path;
            let path_remainder = slice_to_end(path_in_nibble, path_index);
            let shared_len = get_shared_length(node_partial_path, &path_remainder);

            // extension
            // Our extension shares some nibbles.
            // Carry on to the next node.
            if (shared_len == length(node_partial_path)) {
                walk_node_path_inner(
                    trie,
                    current_node.child,
                    path_in_nibble,
                    path_index + shared_len,
                    (move proof)
                )
            } else {
                // Our extension node is not identical to the remainder.
                // We've hit the end of this path
                // updates will need to modify this extension.
                (proof, slice_to_end(path_in_nibble, path_index), Option::none())
            }
        } else {
            // leaf
            let current_node = borrow_as_leaf(&current_node);
            let node_partial_path = &current_node.partial_path;
            let path_remainder = slice_to_end(path_in_nibble, path_index);
            let shared_len = get_shared_length(node_partial_path, &path_remainder);
            if (shared_len == length(&path_remainder) && shared_len == length(node_partial_path)) {
                // The key within this leaf matches our key exactly.
                // Increment the key index to reflect that we have no remainder.
                (proof, Vector::empty(), Option::some(current_node.value))
            } else {
                // or else, insert should branch here, or get return none.
                (proof, slice_to_end(path_in_nibble, path_index), Option::none())
            }
        }
    }

    const KeyReminderEmpty: u64 = 400;
    const LastNodePathEmpty: u64 = 401;
    const LastNodePath_all_Shared: u64 = 402;
    /// Creates new nodes to support k/v pair insertion into a given tree.
    /// @param: `walk_path` path to the node nearest the kv pair.
    /// @param: `key_remainder` Portion of the initial key that must be inserted into the trie.
    /// @param `key` Full original key.
    /// @param `value` Value to insert at the given key.
    /// @return Root hash for the updated trie.
    fun insert_with_walk_path(trie: &mut TrieDB, walk_path: vector<Node>, key_remainer: vector<u8>, key: vector<u8>, value: vector<u8>): HashValue {
        let last_node = Vector::pop_back(&mut walk_path);
        let last_node_type = last_node.ty;

        if (last_node_type == Branch_Node_Type) {
            if (Vector::is_empty(&key_remainer)) {
                // We've found a branch node with the given key.
                // Simply need to update the value of the node to match.
                edit_branch_value(borrow_mut_as_branch(&mut last_node), value);
                Vector::push_back(&mut walk_path, last_node);
            } else {
                // We've found a branch node, but it doesn't contain our key.
                // Reinsert the old branch for now.
                Vector::push_back(&mut walk_path, last_node);
                Vector::push_back(&mut walk_path, make_leaf_node(slice_to_end(&key_remainer, 1), value));
            }
        } else if (last_node_type == Leaf_Node_Type) {
            if (Vector::is_empty(&key_remainer)) {
                // We've found a leaf node with the given key.
                // Simply need to update the value of the node to match.
                edit_leaf_value(borrow_mut_as_leaf(&mut last_node), value);
                Vector::push_back(&mut walk_path, last_node);
            } else {
                let last_node = borrow_as_leaf(&last_node);
                let last_node_partial_path = &last_node.partial_path;
                let shared_nibble_len = get_shared_length(last_node_partial_path, &key_remainer);
                if (shared_nibble_len != 0) {
                    // We've got some shared nibbles between the last node and our key remainder.
                    // We'll need to insert an extension node that covers these shared nibbles.
                    let shared_path = slice(last_node_partial_path, 0, shared_nibble_len);
                    let new_extension_node = make_extension_node(
                        shared_path,
                        node_id_from_hash(hash_value::new(KECCAK256_RLP_NULL_BYTES)) // this child is temporary.
                    );
                    Vector::push_back(&mut walk_path, new_extension_node);
                };

                key_remainer = slice_to_end(&key_remainer, shared_nibble_len);
                let last_node_partial_path = slice_to_end(last_node_partial_path, shared_nibble_len);

                // now, we need to create a branch node to include `key_remainer` and `last_node_partial_path`.
                // and at least one of `key_remainer` and `last_node_partial_path` is not empty.
                Vector::push_back(&mut walk_path, branch_to_node(make_empty_branch_node()));

                if (Vector::is_empty(&last_node_partial_path)) {
                    {
                        let walk_path_len = length(&walk_path);

                        edit_branch_value(borrow_mut_as_branch(Vector::borrow_mut(&mut walk_path, walk_path_len - 1)), last_node.value);
                    };
                    {
                        assert!(!Vector::is_empty(&key_remainer), Errors::invalid_state(KeyReminderEmpty));
                        Vector::push_back(&mut walk_path, make_leaf_node(
                            slice_to_end(&key_remainer, 1),
                            value
                        ));
                    }
                } else if (Vector::is_empty(&key_remainer)) {
                    {
                        let walk_path_len = length(&walk_path);
                        edit_branch_value(borrow_mut_as_branch(Vector::borrow_mut(&mut walk_path, walk_path_len - 1)), value);
                    };

                    {
                        assert!(!Vector::is_empty(&last_node_partial_path), Errors::invalid_state(LastNodePathEmpty));
                        Vector::push_back(&mut walk_path, make_leaf_node(
                            slice_to_end(&last_node_partial_path, 1),
                            last_node.value
                        ));
                    }
                } else {
                    {
                        let walk_path_len = length(&walk_path);
                        edit_branch_index(
                            borrow_mut_as_branch(Vector::borrow_mut(&mut walk_path, walk_path_len - 1)),
                            *Vector::borrow(&last_node_partial_path, 0),
                            save_node(trie, make_leaf_node(
                                slice_to_end(&last_node_partial_path, 1),
                                last_node.value
                            ))
                        );
                    };
                    Vector::push_back(&mut walk_path, make_leaf_node(
                        slice_to_end(&key_remainer, 1),
                        value
                    ))
                };
            }
        } else if (last_node_type == Extension_Node_Type) {
            let last_node = borrow_as_extension(&last_node);
            let last_node_partial_path = &last_node.partial_path;
            let shared_nibble_len = get_shared_length(last_node_partial_path, &key_remainer);
            assert!(shared_nibble_len != length(last_node_partial_path), Errors::invalid_state(LastNodePath_all_Shared));

            if (shared_nibble_len != 0) {
                // We've got some shared nibbles between the last node and our key remainder.
                // We'll need to insert an extension node that covers these shared nibbles.
                let shared_path = slice(last_node_partial_path, 0, shared_nibble_len);
                let new_extension_node = make_extension_node(
                    shared_path,
                    node_id_from_hash(hash_value::new(KECCAK256_RLP_NULL_BYTES)) // this child is temporary.
                );
                Vector::push_back(&mut walk_path, new_extension_node);
            };

            key_remainer = slice_to_end(&key_remainer, shared_nibble_len);
            let last_node_partial_path = slice_to_end(last_node_partial_path, shared_nibble_len);
            // now, we need to create a branch node to include `key_remainer` and `last_node_partial_path`.
            // `last_node_partial_path` cannot be empty.
            Vector::push_back(&mut walk_path, branch_to_node(make_empty_branch_node()));

            let walk_path_len = length(&walk_path);

            {
                if (length(&last_node_partial_path) == 1) {
                    // We're dealing with an unnecessary extension node.
                    // We're going to delete the node entirely.
                    // Simply insert its current value into the branch index.
                    edit_branch_index(
                        borrow_mut_as_branch(Vector::borrow_mut(&mut walk_path, walk_path_len - 1)),
                        *Vector::borrow(&last_node_partial_path, 0),
                        last_node.child
                    );
                } else {
                    // We're dealing with a shrinking extension node.
                    // We need to modify the node to decrease the size of the key.
                    edit_branch_index(
                        borrow_mut_as_branch(Vector::borrow_mut(&mut walk_path, walk_path_len - 1)),
                        *Vector::borrow(&last_node_partial_path, 0),
                        save_node(trie, make_extension_node(slice_to_end(&last_node_partial_path, 1), last_node.child))
                    );
                }
            };


            if (Vector::is_empty(&key_remainer)) {
                edit_branch_value(
                    borrow_mut_as_branch(Vector::borrow_mut(&mut walk_path, walk_path_len - 1)),
                    value);
            } else {
                Vector::push_back(&mut walk_path, make_leaf_node(
                    slice_to_end(&key_remainer, 1),
                    value
                ))
            };
        } else {
            abort Errors::invalid_state(Invalid_Node_Type)
        };

        // now we get all the affacted nodes.
        // we still need to update the hash chain, to get the trie root.
        {
            let reversed_nibble_key = {
                let key = to_nibbles(&key);
                Vector::reverse(&mut key);
                key
            };
            let prev_node_ref = Option::none();
            let i = length(&walk_path);
            while (i > 0) {
                let current_node = Vector::pop_back(&mut walk_path);
                if (current_node.ty == Leaf_Node_Type) {
                    let partial_path = &borrow_as_leaf(&current_node).partial_path;
                    reversed_nibble_key = slice_to_end(&reversed_nibble_key, length(partial_path));
                } else if (current_node.ty == Extension_Node_Type) {
                    let partial_path = &borrow_as_extension(&current_node).partial_path;
                    reversed_nibble_key = slice_to_end(&reversed_nibble_key, length(partial_path));
                    if (Option::is_some(&prev_node_ref)) {
                        let prev_node_ref = Option::extract(&mut prev_node_ref);
                        edit_extension_value(borrow_mut_as_extension(&mut current_node), prev_node_ref);
                    }
                } else if (current_node.ty == Branch_Node_Type) {
                    let current_branch = borrow_mut_as_branch(&mut current_node);
                    if (Option::is_some(&prev_node_ref)) {
                        let prev_node_ref = Option::extract(&mut prev_node_ref);
                        let branch_key = *Vector::borrow(&reversed_nibble_key, 0);
                        edit_branch_index(current_branch, branch_key, prev_node_ref);
                        reversed_nibble_key = slice_to_end(&reversed_nibble_key, 1);
                    }
                };

                prev_node_ref = Option::some(save_node(trie, current_node));

                i = i - 1;
            };
            let root = Option::destroy_some(prev_node_ref);
            // If the root node is < 32 bytes, it won't have a stored hash
            if (root.inline) {
                let hash = hash_value::new(keccak256(root.data));
                if (!Table::contains(&trie.data, hash)) {
                    Table::add(&mut trie.data, hash, root.data);
                };
                hash
            } else {
                hash_value::new(root.data)
            }
        }
    }

    fun save_node(trie: &mut TrieDB, node: Node): ChildReference {
        let encoded_node_data = rlp_encode(&node);
        if (length(&encoded_node_data) < (HASH_LENGTH as u64)) {
            ChildReference {
                inline: true,
                data: encoded_node_data
            }
        } else {
            let hash = hash_value::new(keccak256(encoded_node_data));
            if (!Table::contains(&trie.data, hash)) {
                Table::add(&mut trie.data, hash, encoded_node_data);
            };
            node_id_from_hash(hash)
        }
    }

    const BadHashInStorage: u64 = 500;
    fun get_trie_node(trie: &TrieDB, node_id: ChildReference): Node {
        let node_data = if (node_id.inline) {
            assert!(Vector::length(&node_id.data) < 32, 32);
            node_id.data
        } else {
            assert!(Vector::length(&node_id.data) == 32, 32);
            let node_data = *Table::borrow(&trie.data, hash_value::new(node_id.data));
            // bad hash in storage
            assert!(keccak256(node_data) == node_id.data, Errors::invalid_state(BadHashInStorage));
            node_data
        };
        rlp_decode(&node_data)
    }


    /// Computes the root hash for a trie with a single node.
    /// @param _key Key for the single node.
    /// @param _value Value for the single node.
    /// @return _updatedRoot Hash of the trie.
    fun get_single_node_root_hash(trie: &mut TrieDB, key: vector<u8>, value: vector<u8>): HashValue {
        let dat = make_leaf_node(byte_utils::to_nibbles(&key), value);
        let dat = rlp_encode(&dat);
        let hash = hash_value::new(keccak256(dat));
        if (!Table::contains(&trie.data, hash)) {
            Table::add(&mut trie.data, hash, dat);
        };
        hash
    }
}
