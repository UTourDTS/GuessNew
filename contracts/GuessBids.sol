pragma solidity ^0.4.24;

import "./ProductOwnership.sol";
import "./SaleClockAuction.sol";
import "./ERC20.sol";
import "./GuessEvents.sol";
import "./GuessDatasets.sol";
import "./SafeMath.sol";


/// @title Handles creating auctions for sale and bid of Product.
///  This wrapper of ReverseAuction exists only so that users can create
///  auctions with only one transaction.
contract GuessBids is ProductOwnership, GuessEvents {
    using SafeMath for *;

    // price of guess
    uint256 private rndPrz_ = .001 ether; 
    // min withdraw value         
    uint256 private wthdMin_ = .1 ether; 
    // amount of round at the same time          
    uint256 private rndNum_ = 1; 
    // min token holding 
    uint256 private minHolding = 100; 
    // max amount of players in one round                 
    uint256 private rndMaxNum_ = 200;   
    // max percent of pot for product           
    uint256 private rndMaxPrcnt_ = 50; 
    // total valaut for found            
    uint256 private fndValaut_;  
    // total airdrop in this round                  
    uint256 private airdrop_;                     

    /// @dev erc20 token contract for holding require. it"s UTO by default. 
    ERC20 private erc20;

//==============================================================================
// data used to store game info that changes
//=============================|=============================================
    uint256 public rID_;    // round id number / total rounds that have happened
    uint256 public pID_;    // last player number;
//****************
// PLAYER DATA 
//****************
    // (addr => pID) returns player id by address
    mapping (address => uint256) public pIDxAddr_;  
    // (name => pID) returns player id by name        
    mapping (bytes32 => uint256) public pIDxName_; 
    // (pID => data) player data         
    mapping (uint256 => GuessDatasets.Player) public plyrs_;   
    mapping (uint256 => mapping (uint256 => GuessDatasets.PlayerRounds)) public plyrRnds_;
    // (pID => rID => data) player round data by player id & round id
    mapping (uint256 => mapping (bytes32 => bool)) public plyrNames_;
    // (pID => name => bool) list of names a player owns. 
    // (used so you can change your display name amongst any name you own)
//****************
// ROUND DATA 
//****************
    // (rID => data) round data
    mapping (uint256 => GuessDatasets.Round) public round_; 
    mapping (uint256 => mapping(uint256 => uint256)) public rndTmEth_; 
    // (rID => tID => data) eth in per team, by round id and team id
    // mapping (uint256 => mapping(uint256 => GuessDatasets.PlayerRounds)) public rndPlyrs_;
    // (rID => pID => data) player data in rounds, by round id and player id
    mapping (uint256 => GuessDatasets.PlayerRounds[]) public rndPlyrs_;
//****************
// PRODUCT DATA 
//****************
    // (id => product) product data
    mapping(uint256 => Product) public prdcts_; 

//****************
// PRODUCT DATA 
//****************
    // (address => valaut) valaut of tetants sell product
    mapping(address => uint256) public tetants_; 

//****************
// TEAM FEE DATA 
//****************
    // (team => fees) fee distribution by team
    mapping (uint256 => GuessDatasets.TeamFee) public fees_;  
    // (team => fees) pot split distribution by team        
    mapping (uint256 => GuessDatasets.PotSplit) public potSplit_;     
//****************
// DIVIDE
//****************
    GuessDatasets.Divide private divide_; 

//==============================================================================
// these are safety checks
// modifiers
//==============================================================================
    /**
     * @dev used to make sure no one can interact with contract until it has 
     * been activated. 
     */
    modifier isActivated() {
        require(activated_ == true, "its not ready yet.  check ?eta in discord"); 
        _;
    }
    
    /**
     * @dev prevents contracts from interacting with fomo3d 
     */
    modifier isHuman() {
        address _addr = msg.sender;
        uint256 _codeLength;
        
        assembly {_codeLength := extcodesize(_addr)}
        require(_codeLength == 0, "sorry humans only");
        _;
    }

    /**
     * @dev sets boundaries for incoming tx 
     */
    modifier isWithinLimits(uint256 _eth) {
        require(_eth >= 1000000000, "pocket lint: not a valid currency");
        require(_eth <= 100000000000000000000000, "no vitalik, no");
        _;    
    }

//==============================================================================
// use these to sell product
// saleauction
//==============================================================================
    // @dev set erc20 token contract by address.
    function setERC20(address _address) external onlyCEO {
        erc20 = ERC20(_address);
    } 

    // @notice The auction contract variables are defined in ProductFactory to allow
    //  us to refer to them in ProductOwnership to prevent accidental transfers.
    // `saleAuction` refers to the auction for gen0 and p2p sale of products.
    // `guessBid` refers to the auction for guess price of products.

    /// @dev Sets the reference to the sale auction.
    /// @param _address - Address of sale contract.
    function setSaleAuctionAddress(address _address) external onlyCEO {
        SaleClockAuction candidateContract = SaleClockAuction(_address);

        // NOTE: verify that a contract is what we expect
        require(candidateContract.isSaleClockAuction());

        // Set the new contract address
        saleAuction = candidateContract;
    }

    /// @dev Put a product up for auction.
    ///  Does some ownership trickery to create auctions in one tx.
    function createSaleAuction(
        uint256 _productID,
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration
    )
        external
        // whenNotPaused
    {
        // Auction contract checks input sizes
        // If product is already on any auction, this will throw
        // because it will be owned by the auction contract.
        require(_owns(msg.sender, _productID));
        // Ensure the product is not pregnant to prevent the auction
        // contract accidentally receiving ownership of the child.
        // NOTE: the kitty IS allowed to be in a cooldown.
        _approve(_productID, address(saleAuction));
        // Sale auction throws if inputs are invalid and clears
        // transfer and sire approval after escrowing the kitty.
        saleAuction.createAuction(
            _productID,
            _startingPrice,
            _endingPrice,
            _duration,
            msg.sender
        );
    }

    /// @dev Transfers the balance of the sale auction contract
    /// to the KittyCore contract. We use two-step withdrawal to
    /// prevent two transfer calls in the auction bid function.
    function withdrawAuctionBalances() external onlyCLevel {
        saleAuction.withdrawBalance();
    }

    // @dev set player divide
    function setDivide(uint256 _fnd, uint256 _aff, uint256 _airdrop) external onlyCEO {
        divide_ = GuessDatasets.Divide(_fnd, _aff, _airdrop);
    }

//==============================================================================
// use these to interact with contract
//====|=========================================================================
    /** @dev create r
     */
    // function createRound(
    //     string _name, 
    //     string _nameEn, 
    //     string _disc, 
    //     string _discEn, 
    //     uint256 _price,
    //     uint256 _percent,
    //     uint256 _maxPlayer,
    //     uint256 _lastStartTime
    // ) external only returns (uint256 roundID) { 
    //     uint256 pid = _createProduct(_name, _nameEn, _disc, _discEn, _price, msg.sender);  
    //     // _createProduct(_name, _nameEn, _disc, _discEn, _price, msg.sender); 
    //     uint256 rid = _createRound(pid, _percent, _maxPlayer, _lastStartTime); 
    //     return rID_;   
    // }

    // function _createRound (
    //     uint256 _pid,       
    //     uint256 _percent,
    //     uint256 _maxPlayer,
    //     uint256 _lastStartTime
    // ) 
    //     internal
    //     returns(uint256 rid) 
    // {
    //     GuessDatasets.Round memory _round = GuessDatasets.Round({
    //         plyrCount: 0,
    //         plyrMaxCount: _maxPlayer,
    //         prdctID: _pid,
    //         percent: _percent,

    //         airdrop: 0, 
    //         eth: 0, 
    //         pot: 0, 

    //         strt: _lastStartTime,
    //         end: 0,

    //         price: 0,
    //         winPrice: 0, 
    //         plyr: 0,  
    //         team: 0,
    //         ended: false
    //     });

    //     rID_++;
    //     round_[rID_] = _round;

    //     emit GuessEvents.OnNewRound(rID_);

    //     return rID_;
    // }
    
    /**
     * @dev converts all incoming ethereum to keys.
     * @param _price price of player guess
     * @param _affCode the ID of the player who gets the affiliate fee
     * @param _team what team is the player playing for?
     */
    function guess(uint256 _rID, uint256 _price, uint256 _affCode, uint256 _team)
        isActivated()
        isHuman()
        isWithinLimits(msg.value)
        public
        payable
    {
        // determine if player is new or not
        determinePID(msg.sender);
        
        // fetch player id
        uint256 _pID = pIDxAddr_[msg.sender];
        
        // manage affiliate residuals
        // if no affiliate code was given or player tried to use their own, lolz
        if (_affCode == 0 || _affCode == _pID)
        {
            // use last stored affiliate code 
            _affCode = plyrs_[_pID].laff;
            
        // if affiliate code was given & its not the same as previously stored 
        } else if (_affCode != plyrs_[_pID].laff) {
            // update last affiliate 
            plyrs_[_pID].laff = _affCode;
        }
        
        // verify a valid team was selected
        _team = verifyTeam(_team);
        
        // buy core 
        buyCore(_rID, _price, _affCode, _pID, _team);
    }
    
    
    /**
     * @dev essentially the same as buy, but instead of you sending ether 
     * from your wallet, it uses your unwithdrawn earnings.
     * -functionhash- 0x349cdcac (using ID for affiliate)
     * -functionhash- 0x82bfc739 (using address for affiliate)
     * -functionhash- 0x079ce327 (using name for affiliate)
     * @param _affCode the ID/address/name of the player who gets the affiliate fee
     * @param _team what team is the player playing for?
     * @param _eth amount of earnings to use (remainder returned to gen vault)
     */
    function reLoadXid(uint256 _rID, uint256 _price, uint256 _affCode, uint256 _team, uint256 _eth)
        isActivated()
        isHuman()
        isWithinLimits(_eth)
        public
    {   
        // fetch player ID
        uint256 _pID = pIDxAddr_[msg.sender];
        
        // manage affiliate residuals
        // if no affiliate code was given or player tried to use their own, lolz
        if (_affCode == 0 || _affCode == _pID)
        {
            // use last stored affiliate code 
            _affCode = plyrs_[_pID].laff;
            
        // if affiliate code was given & its not the same as previously stored 
        } else if (_affCode != plyrs_[_pID].laff) {
            // update last affiliate 
            plyrs_[_pID].laff = _affCode;
        }

        // verify a valid team was selected
        _team = verifyTeam(_team);

        // reload core
        reLoadCore(_rID, _pID, _price, _affCode, _team, _eth);
    }

    /**
     * @dev logic runs whenever a reload order is executed.  determines how to handle 
     * incoming eth depending on if we are in an active round or not 
     */
    function reLoadCore(uint256 _rID, uint256 _pID, uint256 _price, uint256 _affID, uint256 _team, uint256 _eth)
        private
    {   
        require(!round_[_rID].ended);
        require(round_[_rID].plyrMaxCount > round_[_rID].plyrCount);
        require(minHolding <= erc20.balanceOf(msg.sender));
        require(plyrRnds_[_pID][_rID].plyrID == 0); 
        
        // grab time
        uint256 _now = now;
        require(_now > round_[_rID].strt);
        
        // sub eth
        plyrs_[_pID].gen = withdrawEarnings(_pID).sub(_eth);

        // call core 
        core(_rID, _pID, _price, msg.value, _affID, _team);

        // if round is over
        if (round_[_rID].plyrMaxCount ==  round_[_rID].plyrCount) 
        {
            endRound(_rID);
        }
    }

    /**
     * @dev withdraws all of your earnings.
     */
    function withdrawValaut()
        isActivated()
        isHuman()
        public
    {        
        // grab time
        uint256 _now = now;
        
        // fetch player ID
        uint256 _pID = pIDxAddr_[msg.sender];
        
        // get their earnings
        uint256 _eth = withdrawEarnings(_pID);

        require(_eth > wthdMin_);
            
        // gib moni
        if (_eth > 0)
            plyrs_[_pID].addr.transfer(_eth);
            
        // fire withdraw event
        emit GuessEvents.OnWithdraw(_pID, msg.sender, _eth, _now);
    }
//==============================================================================
// (for UI & viewing things on etherscan)
//=====_|=======================================================================
    /**
     * @dev returns player earnings per vaults 
     * @return general vault
     * @return airdrop vault
     * @return affiliate vault
     */
    function getPlayerVaults(uint256 _pID)
        public
        view
        returns(uint256 ,uint256, uint256)
    {
        return(
            plyrs_[_pID].gen,
            plyrs_[_pID].airdrop,
            plyrs_[_pID].aff
        );
    }

    /**
     * @dev returns all current round info needed for front end
     * -functionhash- 0x747dff42
     * @return eth invested during ICO phase
     * @return round id 
     * @return total keys for round 
     * @return time round ends
     * @return time round started
     * @return current pot 
     * @return current team ID & player ID in lead 
     * @return current player in leads address 
     * @return current player in leads name
     * @return whales eth in for round
     * @return bears eth in for round
     * @return sneks eth in for round
     * @return bulls eth in for round
     * @return airdrop tracker # & airdrop pot
     */
    function getCurrentRoundInfo()
        public
        view
        returns(uint256, string, string, string, string, uint256, uint256)
    {
        // setup local rID
        uint256 _rID = rID_;
        
        return
        (
            _rID,                           //0
            prdcts_[round_[_rID].prdctID].name,              //1
            prdcts_[round_[_rID].prdctID].nameEn,            //2
            prdcts_[round_[_rID].prdctID].disc,              //3
            prdcts_[round_[_rID].prdctID].discEn,            //4
            prdcts_[round_[_rID].prdctID].price,             //5
            round_[_rID].plyrCount          //6
        );
    }

    /**
     * @dev returns player info based on address.  if no address is given, it will 
     * use msg.sender 
     * @param _addr address of the player you want to lookup 
     * @return player id
     * @return general vault 
     * @return airdrop vault
     * @return affiliate vault 
	 * @return player last round price
     */
    function getPlayerInfoByAddress(address _addr)
        public 
        view 
        returns(uint256, uint256, uint256, uint256, uint256)
    {   
        if (_addr == address(0))
        {
            _addr == msg.sender;
        }
        uint256 _pID = pIDxAddr_[_addr];
        uint256 _rID = plyrs_[_pID].lrnd;
        return
        (
            _pID,                               // 0
            plyrs_[_pID].gen,                    // 1
            plyrs_[_pID].airdrop,                // 2
            plyrs_[_pID].aff,                    // 3
            plyrRnds_[_pID][_rID].price         // 4
        );
    }

//==============================================================================
// this + tools + calcs + modules = our softwares engine
//=====================_|=======================================================
    /**
     * @dev logic runs whenever a buy order is executed.  determines how to handle 
     * incoming eth depending on if we are in an active round or not
     */
    function buyCore(uint _rID, uint256 _price, uint256 _affID, uint256 _pID, uint256 _team)
        private
    {
        require(!round_[_rID].ended);
        require(round_[_rID].plyrMaxCount > round_[_rID].plyrCount);
        require(minHolding <= erc20.balanceOf(msg.sender));
        require(plyrRnds_[_pID][_rID].plyrID == 0); 
        
        // grab time
        uint256 _now = now;
        require(_now > round_[_rID].strt);

        // call core 
        core(_rID, _pID, _price, msg.value, _affID, _team);

        // if round is over
        if (round_[_rID].plyrMaxCount ==  round_[_rID].plyrCount) 
        {
            endRound(_rID);
        } 
    }
    
    /**
     * @dev this is the core logic for any buy/reload that happens while a round 
     * is live.
     */
    function core(uint256 _rID, uint256 _pID, uint256 _price, uint256 _eth, uint256 _affID, uint256 _team)
        private
    {
        GuessDatasets.PlayerRounds memory data = GuessDatasets.PlayerRounds(
            _pID, erc20.balanceOf(msg.sender), _price, now, _team, false);
        // update player 
        // plyrRnds_[_pID][_rID].uto = erc20.balanceOf(msg.sender);
        // plyrRnds_[_pID][_rID].price = _price;
        // plyrRnds_[_pID][_rID].timestamp = now;
        // plyrRnds_[_pID][_rID].team = _team;
        // plyrRnds_[_pID][_rID].iswin = false;
        plyrRnds_[_pID][_rID] = data;
        
        // update round
        round_[_rID].plyrCount = round_[_rID].plyrCount.add(1);
        round_[_rID].eth = _eth.add(round_[_rID].eth);
        rndTmEth_[_rID][_team] = _eth.add(rndTmEth_[_rID][_team]);

        rndPlyrs_[_rID].push(data);

        // distribute eth
        // 2% found 10% aff 10% airdrop %n tenant %m players in round
        uint _left = distributeExternal(_rID, _pID, _eth, _affID);
        distributeInternal(_rID, _left);

        // call end tx function to fire end tx event.
        endTx(_pID, _team, _eth);
    }
//==============================================================================
// tools
//============================================================================== 
    /**
     * @dev gets existing or registers new pID.  use this when a player may be new
     * @return pID 
     */
    function determinePID(address _addr)
        private
        returns (bool)
    {
        uint256 _pID = pIDxAddr_[_addr];
        bool isNew = false;
        // if player is new to this version of fomo3d
        if (_pID == 0)
        {
            // grab their player ID 
            pID_++ ;
            // set up player account 
            pIDxAddr_[_addr] = pID_;
            plyrs_[_pID].addr = _addr;
            isNew = true;
        } 
        return (isNew);
    }
    
    /**
     * @dev checks to make sure user picked a valid team.  if not sets team 
     * to default (sneks)
     */
    function verifyTeam(uint256 _team)
        private
        pure
        returns (uint256)
    {
        if (_team < 0 || _team > 3)
            return(0);
        else
            return(_team);
    }
    
    /**
     * @dev decides if round end needs to be run & new round started.  and if 
     * player unmasked earnings from previously played rounds need to be moved.
     */
    function managePlayer(uint256 _pID)
        private
    {       
        // update player"s last round played
        plyrs_[_pID].lrnd = rID_;
    }
    
    /**
     * @dev ends the round. manages paying out winner/splitting up pot
     */
    function endRound(uint256 _rID) private
    {   
        // get winner
        uint256 _winID;
        uint256 _winPrice;
        uint256 _winPlyrPrice;
        (_winID, _winPrice, _winPlyrPrice) = calWinner(_rID);

        // update round
        round_[_rID].price = _winPrice;
        round_[_rID].winPrice = _winPlyrPrice;
        round_[_rID].plyr = _winID;
        round_[_rID].team = plyrRnds_[_winID][_rID].team;
        round_[_rID].end = now; 
        round_[_rID].ended = true;

        // update player
    }
    
    /**
     * @dev generates a random number between 0-99 and checks to see if thats
     * resulted in an airdrop win
     * @return do we have a winner?
     */
    // function airdrop()
    //     private  
    //     returns(bool)
    // {
        

    //     // 
    // }

    function calWinner(uint256 _rID) 
        private
        view 
        returns (uint256, uint256, uint256) 
    {
        uint256 seed = uint256(keccak256(abi.encodePacked(
            
            (block.timestamp).add
            (block.difficulty).add
            ((uint256(keccak256(abi.encodePacked(block.coinbase)))) / (now)).add
            (block.gaslimit).add
            ((uint256(keccak256(abi.encodePacked(msg.sender)))) / (now)).add
            (block.number)
            
        ))) % 100;

        uint256 _winPrice = prdcts_[round_[_rID].prdctID].price;
        uint256 _diff = _winPrice;
        _winPrice = _winPrice.div(100).mul(seed);

        uint256 _winID;
        uint256 _tmp;
        uint256 _winPlyrPrice;
        
        for(uint256 i = 0; i < rndPlyrs_[_rID].length; i++){
            if ( rndPlyrs_[_rID][i].price > _winPrice ){
                _tmp = rndPlyrs_[_rID][i].price.sub(_winPrice);
            } else {
                _tmp = _winPrice.sub(rndPlyrs_[_rID][i].price);
            }

            if (_tmp < _diff ){
                _diff = _tmp;
                _winID = rndPlyrs_[_rID][i].plyrID;
                _winPlyrPrice = rndPlyrs_[_rID][i].price;
            }
        }

        return (_winID, _winPrice, _winPlyrPrice);
    }

    /**
     * @dev distributes eth based on fees to found, aff
     */
    function distributeExternal(uint256 _rID, uint256 _pID, uint256 _eth, uint256 _affID)
        private 
        returns(uint256)
    {
        uint256 _left = _eth;
        // pay 2% out to community rewards
        uint256 _com = _eth / 50;
        fndValaut_ = _com.add(fndValaut_);
        _left = _eth.sub(_com);
        
        // distribute share to affiliate
        uint256 _aff = _eth / 10;
        
        // decide what to do with affiliate share of fees
        // affiliate must not be self, and must have a name registered
        if (_affID != _pID) {
            plyrs_[_affID].aff = _aff.add(plyrs_[_affID].aff);
            _left = _left.sub(_aff);
            emit GuessEvents.OnAffiliatePayout(_affID, plyrs_[_affID].addr, _rID, _pID, _aff, now);
        }

        // airdrop for all players
        uint256 _airdrop = _eth / 10;
        round_[_rID].airdrop = _airdrop.add(round_[_rID].airdrop);
        _left = _left.sub(_airdrop);
        
        // tetant
        uint256 _percent = round_[_rID].percent;
        uint256 _tenant = _eth.div(100).mul(_percent);

        address _addr = productToOwner[round_[_rID].prdctID];
        tetants_[_addr] = _tenant.add(tetants_[_addr]);
        _left = _left.sub(_tenant);

        return _left;
    }
    
    /**
     * @dev distributes eth based on fees to gen and pot
     */
    function distributeInternal(uint256 _rID, uint256 _eth)
        private
    {
        round_[_rID].pot = _eth.add(round_[_rID].pot);
    }

    
    /**
     * @dev adds up unmasked earnings, & vault earnings, sets them all to 0
     * @return earnings in wei format
     */
    function withdrawEarnings(uint256 _pID)
        private
        returns(uint256)
    {   
        // from vaults 
        uint256 _earnings = (plyrs_[_pID].airdrop).add(plyrs_[_pID].gen).add(plyrs_[_pID].aff);
        if (_earnings > 0)
        {
            plyrs_[_pID].airdrop = 0;
            plyrs_[_pID].gen = 0;
            plyrs_[_pID].aff = 0;
        }

        return(_earnings);
    }
    
    /**
     * @dev prepares compression data and fires event for buy or reload tx"s
     */
    function endTx(uint256 _pID, uint256 _team, uint256 _eth)
        private
    {
        emit GuessEvents.OnEndTx
        (
            msg.sender,
            _pID,
            _team,
            _eth
        );
    }
//==============================================================================
//    (~ _  _    _._|_    .
//    _)(/_(_|_|| | | \/  .
//====================/=========================================================
    /** upon contract deploy, it will be deactivated.  this is a one time
     * use function that will activate the contract.  we do this so devs 
     * have time to set things up on the web end                            **/
    bool public activated_ = false;
    function activate()
        public
    {
        // only team just can activate 
        require(
            msg.sender == 0x4DdFA34d7398aB561d1aF29f237C59032B9C9C4C ||
            msg.sender == 0x121D892dCd8239005f67c8eC311B5B6Fe9af75cF ||
            msg.sender == 0x30884121dcCCf273A0bfd4f68E98b214a900F055 ||
            msg.sender == 0x33BeFF75b5D98AC8dfcB403f4FAb213F62BdEabA,
            "only team just can activate"
        );

		// make sure that its been linked.
        require(address(erc20) != address(0), "must link to other token first");
        
        // can only be ran once
        require(activated_ == false, "Guess already activated");
        
        // activate the contract 
        activated_ = true;
        
        // lets start first round
        rID_ = 1;
    }
}