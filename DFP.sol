// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

error DFP__FundRaisingNotActive();
error DFP__FundRaisingIsEnded();
error DFP__NeedsValueMoreThanZero();
error DFP__OnlyAdministratorCanPerfromThis(); 
error DFP__OnlyContributorCanPerfromThis(); 
error DFP__TargetGoalNotMetCannotTransferAmount();
error DFP__TargetAmountReachedCannotRefund();


contract DecentralizedFundrasingPlatform {

    struct Campaign{
        address creator;
        bytes name;
        string description;
        uint targetAmount;
        uint currentAmount;
        address[] contributors;
        uint deadline;
        bool completed;
    }
    
    ////////////////////
    /// State Variables 
    ///////////////////
    
    uint private campaignId;
    address public immutable administrator; /// Deployer of the contract 
    uint internal constant PRECISION = 1e18;

    /// @dev struct type array for storing all array
    Campaign[] private totalCompaigns;
    /// @dev Mapping of CampignId to Comapign struct
    mapping(uint _campaignId => Campaign ) private compaignIdToCompaign;
    /// @dev Mapping of amount received by specific user on specific campaign
    mapping(uint _compaignId => mapping(address contributor => uint contributedAmount)) private amountRecevied;
   
    ///////////////
    /// Events 
    //////////////

    event CampaignCreation(
        uint indexed camapaignId,
        address indexed creator,
        uint indexed targetAmount,
        uint deadline
    );
    event Contribution(
        uint indexed camapaignId, 
        address indexed contributor, 
        uint indexed amount
    );
    event RefundClaim(
        uint indexed camapaignId, 
        address indexed contributor, 
        uint indexed amount
    ); 
    event CampaignCompleted(
        uint indexed camapaignId, 
        address indexed administrator, 
        uint indexed amount
    ); 

    ///////////////
    /// Modifiers 
    //////////////

    modifier beforeDeadline(uint _compaignId){
        if(block.timestamp >= compaignIdToCompaign[_compaignId].deadline){
            revert DFP__FundRaisingNotActive();
        }  
        _;
    }
    modifier afterDeadline(uint _compaignId){
        if(block.timestamp < compaignIdToCompaign[_compaignId].deadline || compaignIdToCompaign[_compaignId].deadline == 0){
            revert DFP__FundRaisingIsEnded();
        }
        _;
    }

    modifier moreThanZero(uint amount){
        if(amount == 0){
            revert DFP__NeedsValueMoreThanZero();
        }
        _;
    }
    modifier onlyAdmin(){
        if(msg.sender != administrator){
            revert DFP__OnlyAdministratorCanPerfromThis();
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////

    constructor(){
        administrator = msg.sender;
    }

    /*
     * @param _name: The name of the compaign for creating
     * @param _description: The description of the compaign
     * @param _targetAmount: The amount Campaign is targetng
     * @param deadline: The compaign ending time
     * @dev In name bytes are used input only hexadecimal values
     * @notice The deadline should be in unix and name should be in hexadecimal
     * @notice This function will create a new compaign with specific id and creator of compaign
     */
    function addCompaign(
        bytes memory _name,
        string memory _description,
        uint _targetAmount,
        uint deadline
    )   public
        moreThanZero(_targetAmount)
    {
        require(deadline > block.timestamp , "Deadline Must Be Greater Present Time");
        campaignId++;
        Campaign storage campaign = compaignIdToCompaign[campaignId];
        campaign.creator = msg.sender;
        campaign.name = _name;
        campaign.description = _description;
        campaign.targetAmount = _targetAmount;
        campaign.deadline = deadline;
        totalCompaigns.push(campaign);
        emit CampaignCreation(campaignId,msg.sender, _targetAmount, deadline);
    }


    /*
     * @param _compaignId: The CompaignId You want to fund
     * @param _amount: The amount you want to fund
     * @notice Only on active Comapaign you can fund
     * @notice This function will fund to a comapign on comapignId you specified and fund in ether
     */
    function fundComapign(
        uint _campaignId,
        uint _amount
    )   external
        payable
        beforeDeadline(_campaignId)
        moreThanZero(_amount)
    {
        require(msg.value == _amount * PRECISION,"Input Valid Amount"); 
        Campaign storage campaign = compaignIdToCompaign[_campaignId];
        campaign.currentAmount += _amount;
        if(amountRecevied[_campaignId][msg.sender] == 0){
            amountRecevied[_campaignId][msg.sender] += _amount;
            campaign.contributors.push(msg.sender);
        }else{
            amountRecevied[_campaignId][msg.sender] += _amount;
        }
        emit Contribution(_campaignId, msg.sender, _amount);
    }

    /*
     * @param _compaignId: The compaignId you want to refund
     * @notice you can refund only when you have contributed and compaign is ended
     * @notice This function will refund the contributors if compaign targetAmount not received
     * @dev solidity deals with Wei so PRECISION is use for exact amount transfer
     */
    function refund(
        uint _campaignId
    )   external
        afterDeadline(_campaignId)
    {
        require(amountRecevied[_campaignId][msg.sender] > 0,"First Contribute");
        Campaign storage campaign = compaignIdToCompaign[_campaignId];
        if(campaign.currentAmount < campaign.targetAmount /*&& block.timestamp >= compaign.deadline*/) {
            uint balance = amountRecevied[_campaignId][msg.sender];
            campaign.currentAmount -= balance;
            amountRecevied[_campaignId][msg.sender] = 0;
            emit RefundClaim(_campaignId, msg.sender, balance);
            (bool success,)=payable(msg.sender).call{ value: balance * PRECISION }("");
            require(success,"Withdraw Fund Failed");
            
        }else{
            revert DFP__TargetAmountReachedCannotRefund();
        }
    }

    /*
     * @param _compaignId: The compaignId you want to complete
     * @notice This function will transfer the amount to campaign creator and complete the compaign
     * @notice Only deployer can call this function after compaign deadline  
     */
    function completeCampaign(
        uint _campaignId
    )   external
        onlyAdmin
        afterDeadline(_campaignId)
    {
       
        compaignIdToCompaign[_campaignId].completed = true;
        emit CampaignCompleted(_campaignId, msg.sender, compaignIdToCompaign[_campaignId].targetAmount);
        fundTransfer(_campaignId);
    }

    /*
     * @notice This function is called by Administrator for transferring fund to Creator of Campaign  
     */
    function fundTransfer(
        uint _compaignId
    )   private
        onlyAdmin
        afterDeadline(_compaignId)
    {
   
        Campaign storage compaign = compaignIdToCompaign[_compaignId];
        if(block.timestamp >= compaign.deadline && compaign.currentAmount >= compaign.targetAmount){
            uint balance = compaign.currentAmount;
            require(address(this).balance >= balance , "Insufficient Balance For Transfer");
            compaign.currentAmount -= balance;
            (bool success,) = payable(compaign.creator).call{ value: balance * PRECISION }("");
            require(success, "Transfer To Compaign Creator Failed"); 
        }else{
            revert DFP__TargetGoalNotMetCannotTransferAmount();
        }
       
    }

    /*
     * @notice This function is called by Administrator for transferring fund to contributor of Campaign  
     */
    function transferRefund(
        uint _campaignId
    )   external
        onlyAdmin
        afterDeadline(_campaignId) 
    {
        Campaign storage compaign = compaignIdToCompaign[_campaignId];
        require(compaign.currentAmount < compaign.targetAmount,"Target Amount Reached");
        uint length = compaignIdToCompaign[_campaignId].contributors.length;
        for(uint i = 0; i < length; i++){
            uint amount = amountRecevied[_campaignId][compaignIdToCompaign[_campaignId].contributors[i]];
            amountRecevied[_campaignId][compaignIdToCompaign[_campaignId].contributors[i]] -= amount;
            (bool success,)=payable(compaignIdToCompaign[_campaignId].contributors[i]).call{value: amount * PRECISION }("");
            require(success, "Auto Transfer To Contributor Failed");
        }

    }

    ///////////////////////////////
    //  view & pure functions
    ///////////////////////////////

    function getAllContributors(
        uint _campaignId
    )   external 
        view 
        returns(address[] memory contributors , uint[] memory amount)
    {

        uint length = compaignIdToCompaign[_campaignId].contributors.length;
        contributors = new address[](length);
        amount = new uint[](length);

        for(uint i = 0; i < length; i++){
            contributors[i] = compaignIdToCompaign[_campaignId].contributors[i];
            amount[i] = amountRecevied[_campaignId][contributors[i]];
        }

        return(contributors,amount);

    }

    function getCampaign(
        uint _camplainId
    )   external 
        view 
        returns(Campaign memory)
    {
        return compaignIdToCompaign[_camplainId];
    }

    function getTotalComapaign() public view returns(uint){
        return totalCompaigns.length;
    }

    function getPrecisionValue() public pure returns(uint){
        return PRECISION;
    }

    function getAllCompaigns() public view returns(Campaign[] memory campaign){
        uint length = totalCompaigns.length;
        campaign = new Campaign[](length);
        for(uint i = 0; i < length; i++){
            campaign[i] = totalCompaigns[i];
        }

        return campaign;
    }
}