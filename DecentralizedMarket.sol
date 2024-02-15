// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { ReentrancyGuard } from "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol";

error DecentralizedMarketplace__YouCannotHaveAnyOrderYet();
error DecentralizedMarketplace__ConfirmationTimeIsEnded();
error DecentralizedMarletplace__ItemDoesNotExistInTheMarketplace();
error DecentralizedMarketplace__YouAreBlackListedYouCannotTradeInThisMarketplace();
error DecentralizedMarketplace__OutOfStock();

contract DecentralizedMarketplace is ReentrancyGuard {
    enum OrderStatus {
        Pending,
        Confirmed,
        Delivered,
        Disputed
    }

    struct Item {
        uint id;
        bytes name;
        bytes category;
        uint256 cost;
        uint256 stock;
        address owner;
    }

    struct Order {
        address buyer;
        uint256 amountTransfered;
        uint256 amountConfirmed;
        uint256 purchaseTime;
        uint256 confirmationTime;
        OrderStatus status;
        Item items;
    }

    Item[] private totalItems;
    Order[] private totalOrders;
    Order[] private disputedOrders;
    Order[] private completeOrders;
    address[] private blackListed;
    uint256 private itemId;
    address public immutable admin;
    uint public constant PRECISION = 1e18;

    /// @dev Mapping of Categoty to  Item struct
    mapping(bytes Category => mapping(uint256 => Item)) private categoryToItems;
    /// @dev Mapping of Categoty to  Id To Item Exist
    mapping(bytes Category => mapping(uint256 ItemId => bool)) private itemExist;
    /// @dev Mapping of Buyer to Categoty to  Id To Order 
    mapping(address Buyer => mapping(bytes Category => mapping(uint256 ItemId => Order)))
        private orders;
     /// @dev Mapping of Buyer address to  Category To  Item Id  order count of user
    mapping(address Buyer => mapping(bytes Category => mapping(uint256 ItemId => uint256)))
        private orderCount;
    /// @dev Mapping of Buyer address to  Category To  Item Id confirm order of user
    mapping(address Buyer => mapping(bytes => mapping(uint256 => bool))) private  confirmOrders;
    /// @dev Mapping of Categoty to  Id To Owner COnfirmed Amount
    mapping(address Owner => mapping(bytes Category => mapping(uint256 itemId => uint256 confirmedAmount)))
        private OwnerToconfirmAmount;
    /// @dev Mapping of Categoty to  Id To dispute Exist
    mapping(bytes Category => mapping(uint ItemId => bool)) private isDisputeExist;
    /// @dev Mapping of Address to  bool 
    mapping(address => bool) private isBlackListed;
    

    /////////////////
    //// Events
    ////////////////

    event ItemListed(
        address indexed owner,
        bytes indexed category,
        uint indexed itemId,
        uint stock
    );
    
    event StockAdded(
        bytes indexed category,
        uint indexed itemId,
        uint indexed stock,
        uint newCost
    );

    event ItemBought(
        address indexed owner,
        bytes indexed category,
        OrderStatus itemStatus
    );

    event ItemStatus(
        bytes indexed category,
        uint indexed itemId,
        uint indexed time,
        OrderStatus itemStatus
    );

    event DisputeResolve(
        bytes indexed category,
        uint indexed itemId,
        OrderStatus itemStatus
    );

    event AmountWithdraw(
        address indexed owner,
        uint indexed amount
    );

    event CancelListed(
        address indexed owner,
        bytes indexed category,
        uint indexed itemId
    );


    /////////////////
    //// modifiers
    ////////////////

    modifier onlyBuyer(bytes memory _category, uint256 _itemId) {
        require(
            orders[msg.sender][_category][_itemId].buyer == msg.sender,
            "Only Buyer Can Call This"
        );
        _;
    }
    modifier onlyOwner(bytes memory _category, uint256 _itemId) {
        require(
            categoryToItems[_category][_itemId].owner == msg.sender,
            "Only Item Owner Can Call This"
        );
        _;
    }
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only Admin Can Call This Function");
        _;
    }

    modifier onlyExistItem(bytes memory _category, uint256 _itemId) {
        if (itemExist[_category][_itemId]) {
            _;
        } else {
            revert DecentralizedMarletplace__ItemDoesNotExistInTheMarketplace();
        }
    }

    modifier onlyExludedBlacklisted() {
        if (isBlackListed[msg.sender]) {
            revert DecentralizedMarketplace__YouAreBlackListedYouCannotTradeInThisMarketplace();
        } else {
            _;
        }
    }

    modifier isStockAvailable(bytes memory _category, uint _itemId){
        Item storage item = categoryToItems[_category][_itemId];
        if(item.stock > 0){
            _;
        }else{
            revert DecentralizedMarketplace__OutOfStock();
        }
    }

    constructor() {
        admin = msg.sender;
    }

    /////////////////
    //// External Functions
    ////////////////


    /*
     * @param _name: The name of the item for creating
     * @param _category: The _category of the 
     * @param _cost: The cost of time
     * @param _stock: The total number of items 
     * @dev In name category bytes are used input only hexadecimal values
     * @notice Blacklisted address cannot call this function 
     */
    function listItem(
        bytes memory _name,
        bytes memory _category,
        uint256 _cost,
        uint256 _stock
    ) external onlyExludedBlacklisted {
        Item storage item;
        item = categoryToItems[_category][itemId];
        item.id = itemId;
        item.name = _name;
        item.category = _category;
        item.stock = _stock;
        item.cost = _cost * PRECISION;
        item.owner = msg.sender;
        itemExist[_category][itemId] = true;
        totalItems.push(item);
        emit ItemListed(item.owner, _category, itemId, item.stock);
        itemId++;
    }

    /*
     * @param _category: The _category which you want to buy
     * @param _ItemId: The Id of Item Which you want to buy
     * @notice Blacklisted address cannot call this function
     * @notice this function is used for buying single item  
     */
    function buyItem(bytes memory _category, uint256 _itemId)
        external
        payable
        onlyExludedBlacklisted
        onlyExistItem(_category, _itemId)
        isStockAvailable(_category,_itemId)
        nonReentrant    
    {
        Item storage item = categoryToItems[_category][_itemId];
        require(
            msg.value >= item.cost,
            "Value Cannot Match The Cost"
        );
        
        Order storage order = orders[msg.sender][_category][_itemId];
        order.buyer = msg.sender;
        order.amountTransfered += msg.value;
        order.purchaseTime = block.timestamp;
        order.confirmationTime = order.purchaseTime + 2 minutes;
        order.status = OrderStatus.Confirmed;
        order.items = item;
        item.stock -= 1;
        if (item.stock == 0) {
            itemExist[_category][itemId] = false;
        }
        totalOrders.push(order);
        orderCount[msg.sender][_category][_itemId]++;
        emit ItemBought(order.buyer, _category, order.status);
    }

    /*
     * @param _category: The _category which you want to buy
     * @param _ItemId: The Id of Item Which you want to buy
     * @notice Blacklisted address cannot call this function
     * @notice this function is used for buying Stock  
     */
    function buyStock(bytes memory _category, uint256 _itemId)
        external
        payable
        onlyExludedBlacklisted
        onlyExistItem(_category, _itemId)
        isStockAvailable(_category,_itemId)
        nonReentrant 
    {
        Item storage item = categoryToItems[_category][_itemId];
        uint totalCost = item.cost * item.stock;
        require( msg.value >= totalCost,"Value Cannot Match The Stock Cost");
        Order storage order = orders[msg.sender][_category][_itemId];
        order.buyer = msg.sender;
        order.amountTransfered += msg.value;
        order.purchaseTime = block.timestamp;
        order.confirmationTime = order.purchaseTime + 2 minutes;
        order.status = OrderStatus.Confirmed;
        order.items = item;
        item.cost = totalCost;
        item.stock = 0;
        itemExist[_category][itemId] = false;
        totalOrders.push(order);
        orderCount[msg.sender][_category][_itemId]++;
        // addressToOrders[msg.sender]++;
        emit ItemBought(order.buyer, _category, order.status);

    } 

    /*
     * @param _category: The _category which you want to buy
     * @param _ItemId: The Id of Item Which you want to buy
     * @param stockCount: The stock count to add
     * @param newCOst: The new price of the stock
     * @notice Blacklisted address cannot call this function
     * @notice this function is used for adding Stock to Existing Catgory
     */
    function addStock(
        bytes memory _category,
        uint256 _itemId,
        uint256 stockCount,
        uint newCost
    )
        external
        onlyExistItem(_category, _itemId)
        onlyOwner(_category, _itemId)
    {
        Item storage item = categoryToItems[_category][_itemId];
        item.stock += stockCount;
        item.cost += newCost;
        emit StockAdded(_category, _itemId, stockCount,newCost);
    }

    /*
     * @notice This function is called by Buyer of Item for Confirming The order  in Confirm period otherwise it will be automatically confirmed  
     */
    function confirmOrder(
        bytes memory _category,
        uint _itemId,
        OrderStatus _status
    ) external onlyExistItem(_category, _itemId) onlyBuyer(_category, _itemId) nonReentrant
    {
        Order storage order = orders[msg.sender][_category][_itemId];
        if (order.status == OrderStatus.Confirmed) {
            if (block.timestamp <= order.confirmationTime) {
                if (_status == OrderStatus.Delivered) {
                    calculateAmountToConfirm(_category, _itemId, _status);
                } else {
                    order.status = OrderStatus.Disputed;
                    isDisputeExist[_category][_itemId] = true;
                    confirmOrders[msg.sender][_category][_itemId] = false;
                    emit ItemStatus(_category, _itemId, block.timestamp, _status);
                    disputedOrders.push(order);
                }
                
            } else {
                calculateAmountToConfirm(_category, _itemId, OrderStatus.Delivered);  
            }
        } else {
            revert DecentralizedMarketplace__YouCannotHaveAnyOrderYet();
        }
       
    }

    /*
     * @notice This is interal function for couting the amount for withdraw according to number of items
     * @dev Helper Function
     */
    function calculateAmountToConfirm(
        bytes memory _category,
        uint256 _itemId,
        OrderStatus _status
    )   internal
        onlyBuyer(_category,_itemId)
    {
        Order storage order = orders[msg.sender][_category][_itemId];
        order.status = _status;
        uint256 itemCost = categoryToItems[_category][_itemId].cost;
        uint256 orderCountForItem = orderCount[msg.sender][_category][
            _itemId
            ];
        uint256 amountConfirmedForItem = itemCost * orderCountForItem;
        require(order.amountTransfered >= amountConfirmedForItem, "Insufficient amount transferred");
        order.amountConfirmed += amountConfirmedForItem;
        order.amountTransfered -= amountConfirmedForItem;
        confirmOrders[msg.sender][_category][_itemId] = true;
        OwnerToconfirmAmount[categoryToItems[_category][_itemId].owner][
            _category
            ][_itemId] += amountConfirmedForItem;
        emit ItemStatus(_category,_itemId, block.timestamp, _status);
        completeOrders.push(orders[msg.sender][_category][_itemId]);
        //order.status = OrderStatus.Pending;
        //order.amountConfirmed = 0;
        orderCount[msg.sender][_category][_itemId] -= orderCountForItem;

    }
 
    /*
     * @notice This function for Withdrawing the Amount for specific category only by item Owner
     */
    function withDraw(bytes memory _category, uint256 _itemId)
        external
        onlyExistItem(_category, _itemId)
        onlyOwner(_category, _itemId)
        nonReentrant
    {
        require(
            OwnerToconfirmAmount[msg.sender][_category][_itemId] > 0,
            "Amount Must Be Greater Than Zero Wait For Confirmation"
        );
        (bool success, ) = categoryToItems[_category][_itemId].owner.call{
            value: OwnerToconfirmAmount[msg.sender][_category][_itemId]
        }("");
        require(success, "Transfer To Item Owner Failed");
        emit AmountWithdraw(msg.sender, OwnerToconfirmAmount[msg.sender][_category][_itemId]);
        OwnerToconfirmAmount[msg.sender][_category][_itemId] = 0;
    }

    /*
     * @param flag: This param determines whether the buyer receives a refund; otherwise, the owner receives the funds.
     * @notice This function for Resolving the Dispute between Buyer and Seller
     */
    function resolveDispute(
        bytes memory _category,
        uint256 _itemId,
        address buyer,
        bool flag
    ) external onlyExistItem(_category, _itemId) onlyAdmin nonReentrant {
        require(
            orders[buyer][_category][_itemId].status == OrderStatus.Disputed,
            "This Order Is Not Disputed"
        );
        Order storage order = orders[buyer][_category][_itemId];
        address recipient = flag ? order.buyer : order.items.owner;
        transferTo(recipient, order.amountTransfered);
        isDisputeExist[_category][_itemId] = false;
        emit DisputeResolve(_category, _itemId,OrderStatus.Pending);
        orders[buyer][_category][_itemId].status = OrderStatus.Pending;
        orderCount[orders[buyer][_category][_itemId].buyer][_category][_itemId] = 0;
        confirmOrders[buyer][_category][_itemId] = true;
    }

    /*
     * @notice This is interal function for  the amount transfer either to owner or buyer
     * @dev Helper Function
     */
    function transferTo(
        address user,
        uint256 amount
    ) internal onlyAdmin {
        (bool success, ) = payable(user).call{value: amount}("");
        require(success, "Transfer failed");
        
    }

    /*
     * @notice This function is for cancel the listing from marketplace
     */
    function cancelListing(
        bytes memory _category,
        uint256 _itemId
    ) external onlyExistItem(_category, _itemId) onlyOwner(_category, _itemId) {
        require(orders[msg.sender][_category][_itemId].items.stock > 0, "Out of Stock The Stock is Sold!");
        bool hasActiveOrder = false;
        for (uint256 i = 0; i < totalOrders.length; i++) {
            bytes memory category = totalOrders[i].items.category;
            uint256 _ItemId = totalOrders[i].items.id;
            if (keccak256(abi.encodePacked(category)) == keccak256(abi.encodePacked(_category)) &&
                _ItemId == _itemId &&
                !confirmOrders[totalOrders[i].buyer][_category][_itemId]) {
                hasActiveOrder = true;
                break;
            }
        }

        require(!hasActiveOrder, "Cannot cancel a listing with active orders or dispute check");
        emit CancelListed(msg.sender, _category, _itemId);
        delete categoryToItems[_category][_itemId];
        itemExist[_category][_itemId] = false;
    }



    /*
     * @notice This function is used for adding the addresses in blacklist only admin can do this
     */
    function includeInBlacklist(address _user) external onlyAdmin {
        require(_user != address(0), "You Cannot Include Address Zero");
        require(!isBlackListed[_user], "User Already BlackListed");
        blackListed.push(_user);
        isBlackListed[_user] = true;
    }

    /*
     * @notice This function is used for removing the addresses from blacklist only admin can do this
     */
    function excludeFromBlacklist(address _user) external onlyAdmin {
        require(_user != address(0), "You Cannot Exclude Address Zero");
        require(isBlackListed[_user], "User Is Not Blacklisted");
        for (uint256 i = 0; i < blackListed.length; i++) {
            if (blackListed[i] == _user) {
                address temp = blackListed[i];
                blackListed[i] = blackListed[blackListed.length - 1];
                blackListed[blackListed.length - 1] = temp;
                break;
            }
        }

        blackListed.pop();
        isBlackListed[_user] = false;
    }


    ////////////////////
    //// Extenral View
    ///////////////////



    function getOrderStatus(bytes memory _category, uint256 _itemId)
        external
        view
        onlyExistItem(_category, _itemId)
        onlyBuyer(_category, _itemId)
        returns (OrderStatus)
    {
        return orders[msg.sender][_category][_itemId].status;
    }

    function getOrderCount(bytes memory _category, uint256 _itemId)
        external
        view
        onlyExistItem(_category, _itemId)
        onlyBuyer(_category, _itemId)
        returns (uint256)
    {
        return orderCount[msg.sender][_category][_itemId];
    }

    function getTotalItems() external onlyExludedBlacklisted view returns (uint) {
        require(totalItems.length > 0, "No Item In MarketPlace");
        return totalItems.length;
    }

    function getRemainingStock(bytes memory _category, uint256 _itemId)
        external
        view
        onlyExistItem(_category, _itemId)
        onlyExludedBlacklisted
        returns (uint256)
    {
        return categoryToItems[_category][_itemId].stock;
    }

    function getTotalOrders() external onlyExludedBlacklisted view returns (uint) {
        require(totalOrders.length > 0, "No Orders Yet");
        return totalOrders.length;
    }

    function getAllCompletedOrders() external onlyExludedBlacklisted view returns (Order[] memory) {
        require(completeOrders.length > 0, "No Orders Yet");
        return completeOrders;
    }

    function getAllDisputedOrders() external onlyExludedBlacklisted view returns (Order[] memory) {
        require(disputedOrders.length > 0, "No Orders Yet");
        return disputedOrders;
    }

    function getConfirmAmount(
        bytes memory _category,
        uint _itemId
    )   external
        view
        onlyExistItem(_category, _itemId)
        onlyOwner(_category,_itemId)
        returns(uint)
    {
        return OwnerToconfirmAmount[msg.sender][_category][_itemId];
    }


}
