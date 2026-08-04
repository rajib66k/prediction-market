// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/**
 * @title ERC1155TokenReceiver
 * @author Rajib Kumar Pradhan
 * @notice Default ERC1155 token receiver that accepts all transfers.
 */
contract ERC1155TokenReceiver {
    /**
     * @notice Handles receipt of a single ERC1155 token.
     * @return The function selector for acceptance.
     */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external virtual returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    /**
     * @notice Handles receipt of a batch of ERC1155 tokens.
     * @return The function selector for acceptance.
     */
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }
}
