// SPDX-License-Identifier: MIT
// Modified version of OpenZeppelin Contracts v4.4.1 (token/ERC1155/ERC1155.sol)
//https://github.com/OpenZeppelin/openzeppelin-contracts/commit/3dfc0a44f8ca97dec5a734ff9bd73449ef87f7b4

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
/**
 * @dev Implementation of the basic standard multi-token.
 * Customized for VaultHealer: Balances use signed integers, and negative values in a user's balance can be used to offset unearned portions of a pool
    ReentrancyGuard is also included.
 * See https://eips.ethereum.org/EIPS/eip-1155
 * Originally based on code by Enjin: https://github.com/enjin/erc-1155
 *
 * _Available since v3.1._
 *
 * 
 */
abstract contract VH1155 is ERC1155, ReentrancyGuard {
    using Address for address;

    // Mapping from token ID to account balances
    mapping(uint256 => mapping(address => int256)) internal _balances;

    /**
     * @dev See {IERC1155-balanceOf}.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) public view virtual override returns (uint256) {
        require(account != address(0), "ERC1155: balance query for the zero address");
        int balance = _balances[id][account];
        return balance > 0 ? uint(balance) : 0;
    }


    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual override {
        require(to != address(0), "ERC1155: transfer to the zero address");

        address operator = _msgSender();
        uint256[] memory ids = __asSingletonArray(id);
        uint256[] memory amounts = __asSingletonArray(amount);

        _beforeTokenTransfer(operator, from, to, ids, amounts, data);

        require(balanceOf(from, id) >= amount, "ERC1155: insufficient balance for transfer"); //Modified to use unsigned integer balances
        _balances[id][from] -= toInt(amount);

        _balances[id][to] += toInt(amount);

        emit TransferSingle(operator, from, to, id, amount);

        __doSafeTransferAcceptanceCheck(operator, from, to, id, amount, data);

        _afterTokenTransfer(operator, from, to, ids, amounts, data);
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");
        require(to != address(0), "ERC1155: transfer to the zero address");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            int256 amount = toInt(amounts[i]);

            require(balanceOf(from, id) >= amounts[i], "ERC1155: insufficient balance for transfer"); //Modified to use unsigned unsigned integer balances
            _balances[id][from] -= amount;
            _balances[id][to] += amount;
        }

        emit TransferBatch(operator, from, to, ids, amounts);

        __doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, amounts, data);

        _afterTokenTransfer(operator, from, to, ids, amounts, data);
    }

    /**
     * @dev Creates `amount` tokens of token type `id`, and assigns them to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual override {
        require(to != address(0), "ERC1155: mint to the zero address");

        address operator = _msgSender();
        uint256[] memory ids = __asSingletonArray(id);
        uint256[] memory amounts = __asSingletonArray(amount);

        _beforeTokenTransfer(operator, address(0), to, ids, amounts, data);

        _balances[id][to] += toInt(amount); //Modified to use unsigned unsigned integer balances
        emit TransferSingle(operator, address(0), to, id, amount);

        __doSafeTransferAcceptanceCheck(operator, address(0), to, id, amount, data);

        _afterTokenTransfer(operator, address(0), to, ids, amounts, data);
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_mint}.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function _mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        require(to != address(0), "ERC1155: mint to the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, address(0), to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; i++) {
            _balances[ids[i]][to] += toInt(amounts[i]); //Modified to use unsigned unsigned integer balances
        }

        emit TransferBatch(operator, address(0), to, ids, amounts);

        __doSafeBatchTransferAcceptanceCheck(operator, address(0), to, ids, amounts, data);

        _afterTokenTransfer(operator, address(0), to, ids, amounts, data);
    }

    /**
     * @dev Destroys `amount` tokens of token type `id` from `from`
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `from` must have at least `amount` tokens of token type `id`.
     */
    function _burn(
        address from,
        uint256 id,
        uint256 amount
    ) internal virtual override {
        require(from != address(0), "ERC1155: burn from the zero address");

        address operator = _msgSender();
        uint256[] memory ids = __asSingletonArray(id);
        uint256[] memory amounts = __asSingletonArray(amount);

        _beforeTokenTransfer(operator, from, address(0), ids, amounts, "");

        require(balanceOf(from, id) >= amount, "ERC1155: burn amount exceeds balance"); //Modified to use unsigned integer balances
        _balances[id][from] -= toInt(amount);


        emit TransferSingle(operator, from, address(0), id, amount);

        _afterTokenTransfer(operator, from, address(0), ids, amounts, "");
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_burn}.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     */
    function _burnBatch(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal virtual override {
        require(from != address(0), "ERC1155: burn from the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, address(0), ids, amounts, "");

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            require(balanceOf(from, id) >= amount, "ERC1155: burn amount exceeds balance");
            _balances[id][from] = toInt(amount);
        }

        emit TransferBatch(operator, from, address(0), ids, amounts);

        _afterTokenTransfer(operator, from, address(0), ids, amounts, "");
    }

    /**
     * @dev Hook that is called after any token transfer. This includes minting
     * and burning, as well as batched variants.
     *
     * The same hook is called on both single and batched variants. For single
     * transfers, the length of the `id` and `amount` arrays will be 1.
     *
     * Calling conditions (for each `id` and `amount` pair):
     *
     * - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * of token type `id` will be  transferred to `to`.
     * - When `from` is zero, `amount` tokens of token type `id` will be minted
     * for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens of token type `id`
     * will be burned.
     * - `from` and `to` are never both zero.
     * - `ids` and `amounts` have the same, non-zero length.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {}

    function __doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) private {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155Received.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }

    function __doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) private {
        if (to.isContract()) {
            try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (
                bytes4 response
            ) {
                if (response != IERC1155Receiver.onERC1155BatchReceived.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }

    function __asSingletonArray(uint256 element) private pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

    function toInt(uint256 n) private pure returns (int256) {
        require(n <= uint(type(int256).max), "VH: amount is too large");
        return int256(n);
    }
}