pragma solidity ^0.4.24;

import "./GuessAccessControl.sol";


/// @title Base contract for Guess. Holds all common structs, events and base variables.
/// @author lihongzhen
contract ProductFactory is GuessAccessControl {
    /*** EVENTS ***/

    /// @dev create new product, will start a new game
    event CreateProduct(
        address owner, 
        uint256 productId, 
        string _name, 
        string _disc, 
        uint256 _price
    );

    /// @dev Transfer event as defined in current draft of ERC721. Emitted every time a product
    ///  ownership is assigned, including create.
    event Transfer(address from, address to, uint256 tokenId);
    
    /*** DATA TYPES ***/
    struct Product {
        // name of product in english.
        string name;

        // discription of product in English.
        string disc;

        // reference price for the market.
        uint256 price;

        // The timestamp from the block when this cat came into existence.
        uint256 createTime;
    }
    /*** STORAGE ***/

    /// @dev An array containing the Products struct for all Product in existence. The ID
    ///  of each product is actually an index into this array. Note that ID 0 is invalid.
    Product[] public products;

    /// @dev A mapping from product IDs to the address that owns them. All products have
    ///  some valid owner address.
    mapping (uint256 => address) public productToOwner;

    // @dev A mapping from owner address to count of tokens that address owns.
    //  Used internally inside balanceOf() to resolve ownership count.
    mapping (address => uint256) ownerProductCount;

    /// @dev A mapping from ProductIDs to an address that has been approved to call
    ///  transferFrom(). Each Product can only have one approved address for transfer
    ///  at any time. A zero value means no approval is outstanding.
    mapping (uint256 => address) public productToApproved;

    /// @dev Assigns ownership of a specific Product to an address.
    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        // Since the number of products is capped to 2^32 we can"t overflow this
        ownerProductCount[_to]++;
        // transfer ownership
        productToOwner[_tokenId] = _to;
        // When creating new products _from is 0x0, but we can"t account that address.
        if (_from != address(0)) {
            ownerProductCount[_from]--;
            // clear any previously approved ownership exchange
            delete productToApproved[_tokenId];
        }
        // Emit the transfer event.
        // emit Transfer(_from, _to, _tokenId);
    }

    /// @dev An internal method that creates a new product and stores it. This
    ///  method doesn"t do any checking and should only be called when the
    ///  input data is known to be valid. Will generate both a CreateProduct event
    ///  and a Transfer event.
    /// @param _name The name of product in English.
    /// @param _disc The discription of product in English.
    /// @param _price The reference price of Product for the market.
    /// @param _owner The inital owner of this product, must be non-zero.
    function _createProduct(
        string _name, 
        string _disc, 
        uint256 _price,
        address _owner
    )
        internal
        onlyMCH
        returns (uint256)
    {
        Product memory _product = Product({
            name: _name,
            disc: _disc,
            price: _price,
            createTime: now
        });

        uint256 newProductId = products.push(_product) - 1;

        // emit the CreateProduct event
        emit CreateProduct(
            _owner,
            newProductId,
            _name,
            _disc,
            _price
        );

        // This will assign ownership, and also emit the Transfer event as
        // per ERC721 draft
        _transfer(address(0), _owner, newProductId);

        return newProductId;
    }
}