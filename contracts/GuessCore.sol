pragma solidity ^0.4.24;

import "./ProductOwnership.sol";
import "./ERC20.sol";
import "./GuessEvents.sol";
import "./GuessDatasets.sol";
import "./SafeMath.sol";
import "./ProductFactory.sol";


/// @title logic core
contract GuessCore is ProductOwnership, GuessEvents {
    using SafeMath for *;

    // price of guess
    uint256 private rndPrz_ = .001 ether; 
    // min withdraw value         
    uint256 private wthdMin_ = .1 ether; 
    // amount of round at the same time          
    uint256 private rndNum_ = 1; 
    // max amount of players in one round                 
    uint256 private rndMaxNum_ = 200;   
    // max percent of pot for product           
    uint256 private rndMaxPrcnt_ = 50; 
    // total valaut for found            
    uint256 private fndValaut_;  
    // total airdrop in this round                  
    uint256 private airdrop_; 
    // amount of players who in airdrop
    uint256 private airdropCount_ = 5;   

    ERC20 public erc20;

//*******
// data used to store game info that changes
//*******
    // total rounds that have happened
    uint256 public roundID_; 
    // last player number;
    uint256 public playerID_; 
    //rid returns pagesize
    uint256 private pageSize_ = 50;   
//*******
// PLAYER DATA 
//*******
    // (addr => pID) returns player id by address
    mapping (address => uint256) public pIDxAddr_;
    // (pID => data) player data       
    mapping (uint256 => GuessDatasets.Player) public plyrs_;   
    // (pID => rID => data) player round data by player id & round id
    mapping (uint256 => mapping (uint256 => GuessDatasets.PlayerRounds)) public plyrRnds_;  
//*******
// ROUND DATA 
//*******
    // (rID => data) round data
    mapping (uint256 => GuessDatasets.Round) public round_; 
    // (rID => pID => data) player data in rounds, by round id and player id
    mapping (uint256 => GuessDatasets.PlayerRounds[]) public rndPlyrs_;

//*******
// PRODUCT DATA 
//*******
    // (address => valaut) valaut of tetants sell product
    mapping(address => uint256) public tetants_; 
 
//*******
// DIVIDE
//*******
    GuessDatasets.Divide private divide_; 
    
    constructor () public {
        ceoAddress = msg.sender;
        cooAddress = msg.sender;
        merchants[msg.sender] = 1;

        playerID_ = 0;
        roundID_ = 0;
    }

//*******
// modifiers
//*******
    modifier isActivated() {
        require(activated_ == true, "its not ready yet."); 
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
        require(_eth >= 1000000000000000, "pocket lint: not a valid currency");
        require(_eth <= 100000000000000000000000, "no vitalik, no");
        _;    
    }
//*******
// settings
//*******
    function setERC20(address _address) external onlyCEO {
        erc20 = ERC20(_address);
    } 

    function getTokenBalance(address _address) view public returns (uint256){
        return erc20.balanceOf(_address);
    }

    function setDivide(uint32 _fnd, uint32 _aff, uint32 _airdrop) external onlyCEO {
        divide_ = GuessDatasets.Divide(_fnd, _aff, _airdrop);
    }

    function setPriceOfGuess(uint256 _price) external onlyCEO {
        rndPrz_ = _price;
    }

    function setMinWithDraw(uint256 _minWithDraw) external onlyCEO {
        wthdMin_ = _minWithDraw;
    }

    function setActiveRoundNum(uint256 _activeRoundCount) external onlyCEO {
        rndNum_ = _activeRoundCount;
    }

    function setRoundMaxPlayers(uint256 _maxPlayers) external onlyCEO {
        rndMaxNum_ = _maxPlayers;
    }

    function setAirdropCount(uint256 _maxPlayers) external onlyCEO {
        airdropCount_ = _maxPlayers;
    }
  
//*******
// use these to interact with contract
//*******
    /** @dev create round
     */
    function createRound (
        string _name, 
        string _disc, 
        uint256 _price,
        uint256 _percent,
        uint256 _maxPlayer,
        uint256 _holdUto,
        uint256 _lastStartTime
    ) 
        public 
        onlyMCH 
        returns (uint256 roundID) 
    { 
        require(_maxPlayer > 1, "must 2+ players!");

        uint256 pid = _createProduct(_name,_disc,_price, msg.sender);
        uint256 rid = _createRound(pid, _percent, _maxPlayer,_holdUto,_lastStartTime); 
        return rid;
    }

    function _createRound (
        uint256 _pid,       
        uint256 _percent,
        uint256 _maxPlayer,
        uint256 _holdUto,
        uint256 _lastStartTime
    ) 
        internal 
        returns(uint256 rid)
    {
        roundID_++;

        round_[roundID_].prdctID = _pid;
        round_[roundID_].percent = _percent;
        round_[roundID_].plyrMaxCount = _maxPlayer;
        round_[roundID_].holdUto = _holdUto;
        round_[roundID_].strt = _lastStartTime;
        
        emit GuessEvents.OnNewRound(roundID_);

        return roundID_;
    }
    
    /**
     * @dev converts all incoming ethereum to keys.
     * @param _price price of player guess
     * @param _affCode the ID of the player who gets the affiliate fee
     */
    function guess(uint256 _rID, uint256 _price, uint256 _affCode)
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
            plyrs_[_pID].laff = _affCode;
        }
        
        buyCore(_rID, _price, _affCode, _pID);

        emit GuessEvents.OnGuess(_rID, _pID, _price, _affCode, now, msg.sender);
    }
    /**
     * @dev withdraws all of your earnings.
     */
    function withdrawValaut()
        isActivated()
        isHuman()
        public
    {        
        uint256 _now = now;
        uint256 _pID = pIDxAddr_[msg.sender];

        uint256 _eth = withdrawEarnings(_pID);

        require(_eth > wthdMin_, "must more than min withdraw");

        if (_eth > 0)
            plyrs_[_pID].addr.transfer(_eth);

        emit GuessEvents.OnWithdraw(_pID, msg.sender, _eth, _now);
    }
//*******
// (for UI & viewing things on etherscan)
//*******
    /**
     * @dev returns player earnings per vaults 
     * @return general / airdrop /affiliate vault
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
     * @return eth invested during ICO phase
     * @return round id 
     */
    function getCurrentRoundInfo()
        public
        view
        returns(uint256, string, string, uint256, uint256)
    {
        // setup local rID
        uint256 _rID = roundID_;
        uint256 _prdctID = round_[_rID].prdctID;
        
        return
        (
            _rID,
            products[_prdctID].name,
            products[_prdctID].disc,
            products[_prdctID].price,
            round_[_rID].plyrCount
        );
    }

    /**
     * @dev returns player info based on address.  if no address is given, it will 
     * use msg.sender 
     * @param _addr address of the player you want to lookup 
     * @return player id, general vault, airdrop vault,affiliate vault,player last round price
     */
    function getPlayerInfoByAddress(address _addr)
        public 
        view 
        returns(uint256, uint256, uint256, uint256, uint256, address)
    {   
        if (_addr == address(0))
        {
            _addr = msg.sender;
        }
        uint256 _pID = pIDxAddr_[_addr];
        return getPlayerInfoByID(_pID);
    }

    function getPlayerInfoByID(uint256 _pID)
        public 
        view 
        returns(uint256, uint256, uint256, uint256, uint256, address)
    {   
        uint256 _rID = plyrs_[_pID].lrnd;
        return
        (
            _pID,
            plyrs_[_pID].gen,
            plyrs_[_pID].airdrop,
            plyrs_[_pID].aff,
            plyrRnds_[_pID][_rID].price,
            plyrs_[_pID].addr
        );
    }

//*******
// engine
//*******
    /**
     * @dev logic runs whenever a buy order is executed.  determines how to handle 
     * incoming eth depending on if we are in an active round or not
     */
    function buyCore(uint _rID, uint256 _price, uint256 _affID, uint256 _pID)
        private
    {
        require(!round_[_rID].ended, "round over, join next round");
        require(round_[_rID].plyrMaxCount > round_[_rID].plyrCount, "more players, join next round");
        require(plyrRnds_[_pID][_rID].plyrID == 0, "already joined");  

        uint256 holdToken = getTokenBalance(msg.sender);
        require(round_[_rID].holdUto <= holdToken.sub(plyrs_[_pID].lockUto), "not holding enough uto");

        uint256 _now = now;
        require(_now > round_[_rID].strt, "not start, please wait");

        core(_rID, _pID, _price, msg.value, _affID);

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
    function core(uint256 _rID, uint256 _pID, uint256 _price, uint256 _eth, uint256 _affID)
        private
    {
        GuessDatasets.PlayerRounds memory data = GuessDatasets.PlayerRounds(
            _pID, getTokenBalance(msg.sender), _price, now, false);
        // update player round
        plyrRnds_[_pID][_rID].plyrID = _pID;
        plyrRnds_[_pID][_rID].uto = getTokenBalance(msg.sender);
        plyrRnds_[_pID][_rID].price = _price;
        plyrRnds_[_pID][_rID].timestamp = now;
        plyrRnds_[_pID][_rID].iswin = false;
        
        // update round
        round_[_rID].plyrCount = round_[_rID].plyrCount.add(1);
        round_[_rID].eth = _eth.add(round_[_rID].eth);

        rndPlyrs_[_rID].push(data);

        // distribute eth
        // 2% found 10% aff 10% airdrop %n tenant %m players in round
        uint _left = distributeExternal(_rID, _pID, _eth, _affID);
        distributeInternal(_rID, _left);

        // update player
        plyrs_[_pID].lrnd = _rID;
        plyrs_[_pID].lockUto = plyrs_[_pID].lockUto.add(round_[_rID].holdUto);
    }
    
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
        if (_pID == 0)
        {
            playerID_++ ;
            // set up player account 
            pIDxAddr_[_addr] = playerID_;
            plyrs_[playerID_].addr = _addr;
            isNew = true;
        } 
        return (isNew);
    }
    
    /**
     * @dev decides if round end needs to be run & new round started.  and if 
     * player unmasked earnings from previously played rounds need to be moved.
     */
    function managePlayer(uint256 _pID)
        private
    {       
        // update player"s last round played
        plyrs_[_pID].lrnd = roundID_;
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
        address _from;
        address _to;
        uint256 _prdctID;
        
        (_winID, _winPrice, _winPlyrPrice) = calWinner(_rID);

        // update round
        round_[_rID].price = _winPrice;
        round_[_rID].plyr = _winID;
        round_[_rID].end = now; 
        round_[_rID].ended = true;

        // update player
        plyrRnds_[_rID][_winID].iswin = true;
        plyrs_[_winID].lockUto = plyrs_[_winID].lockUto.sub(plyrRnds_[_rID][_winID].uto);

        //transfer token
        _prdctID = round_[_rID].prdctID;
        _from = productToOwner[_prdctID];
        _to = plyrs_[_winID].addr;

        require(_to != address(0), "no winner");

        _transfer(_from, _to, _prdctID);

        emit GuessEvents.OnEndRound(_rID, _winID, _winPrice, round_[_rID].end, plyrs_[_winID].addr);
    }

    /**
     * @dev force end round when too long time, only by ceo 
     */
    function forceEndRound(uint256 _rID) 
        external 
        onlyCEO 
    {
        endRound(_rID);
    }

    /**
     * @dev airdrop to random players
     */
    function lottyAirdrop(uint256 _valaut)
        external
        onlyCEO
    {
        require(_valaut <= airdrop_, "not enough airdrop valaut");
        uint256 _airdropCount = getAirdropCount();
        require(_airdropCount > 0, "no player");
        uint256[] memory _airdopPlayers = getAirdropPlayers(_airdropCount);

        uint256 _tmpPID = 0;
        uint256 _avgValaut = _valaut.div(_airdropCount);
        for(uint256 i = 0; i < _airdopPlayers.length; i++){
            _tmpPID = _airdopPlayers[i];
            plyrs_[_tmpPID].airdrop = _avgValaut;
        }

        emit GuessEvents.OnAirdrop(_valaut, _airdropCount, now);
    }

    /***
     * @dev if total player less than airdropCount_, then all players
     * returns less between airdropCount_ and playerID_
     */
    function getAirdropCount() 
        private 
        view 
        returns (uint256)
    {
        if (airdropCount_ > playerID_){
            return playerID_;
        }
        return airdropCount_;
    }

    /***
     * @dev getAirdropPlayers who will get airdrop
     */
    function getAirdropPlayers(uint256 _count) 
        private 
        view 
        returns (uint256[] memory _airdropPlayers) 
    {
        uint256[] memory pidArr = new uint256[](_count);
        uint256 i = 0;
        uint256 nonce = 1;
        uint256 random;
        while (i < _count) {
            random = getRandomPlayerID(nonce);
            if ( !existInArray(random, pidArr)){
                pidArr[i] = random;
                i++;
            }
            nonce++;
        }

        return pidArr;
    }

    function existInArray(uint256 _pID, uint256[] memory arr) 
        private 
        pure 
        returns(bool) 
    {
        bool _exist = false;
        for(uint32 i = 0; i < arr.length; i++){
            if(arr[i] == _pID) {
                _exist = true;
                break;
            }
        }
        
        return _exist;
    }

    function getRandomPlayerID(uint256 idx) 
        private
        view 
        returns (uint256)
    {
        uint256 random = uint256(keccak256(abi.encodePacked(
            (block.difficulty).add(idx))));
        return  random % playerID_;
    }

    /***
     * @dev calculate random winprice and the winner
     * @param _rID round id
     *  winID winner's playerID
        winPrice random price for award
        winPlyrPrice price of player who is winner
     */
    function calWinner(uint256 _rID) 
        private
        view 
        returns (uint256, uint256, uint256) 
    {
        uint256 _tmp;

        uint256 _winPrice;

        uint256 seed = uint256(keccak256(abi.encodePacked(
            
            (block.timestamp).add
            (block.difficulty).add
            ((uint256(keccak256(abi.encodePacked(block.coinbase)))) / (now)).add
            (block.gaslimit).add
            ((uint256(keccak256(abi.encodePacked(msg.sender)))) / (now)).add
            (block.number)
            
        ))) % 10000;
        
        uint256 _prdctID = round_[_rID].prdctID;
        
        _winPrice = products[_prdctID].price.div(10000).mul(seed);

        if ( rndPlyrs_[_rID][0].price > _winPrice ){
            _tmp = rndPlyrs_[_rID][0].price.sub(_winPrice);
        } else {
            _tmp = _winPrice.sub(rndPlyrs_[_rID][0].price);
        }

        uint256 _diff = _tmp;
        uint256 _winID = rndPlyrs_[_rID][0].plyrID;
        uint256 _winPlyrPrice = rndPlyrs_[_rID][0].price;
        
        for(uint256 i = 0; i < rndPlyrs_[_rID].length; i++){
            if ( rndPlyrs_[_rID][i].price > _winPrice ){
                _tmp = rndPlyrs_[_rID][i].price.sub(_winPrice);
            } else {
                _tmp = _winPrice.sub(rndPlyrs_[_rID][i].price);
            }
            
            if ( _tmp < _diff ){
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
        airdrop_ = _airdrop.add(airdrop_);
        _left = _left.sub(_airdrop);
        
        // tetant
        uint256 _percent = round_[_rID].percent;
        uint256 _tenant = _eth.div(100).mul(_percent);

        uint256 _prdctID = round_[_rID].prdctID;
        address _addr = productToOwner[_prdctID];
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
     * only called by one time
     **/
    bool public activated_ = false;
    function activate()
        public
        onlyCLevel
    {
        require(address(erc20) != address(0), "must link to other token first");
        require(activated_ == false, "Guess already activated");
        activated_ = true;
    }

    function getRoundProductDetail(uint256 _rid) 
        public 
        view 
        returns(uint256 _plyrCount,uint256 _plyrMaxCount,uint256 _prdctID,uint256 _price,uint256 _plyr, bool _ended,  string _name, 
        string _disc, uint256 _referencePrice, address _addr)
    {
        GuessDatasets.Round storage  round = round_[_rid];
        uint256 pid = round.prdctID;
        ProductFactory.Product storage product = ProductFactory.products[pid];
        return (round.plyrCount, round.plyrMaxCount, round.prdctID, round.price, round.plyr, round.ended, product.name,
            product.disc,product.price, plyrs_[round.plyr].addr);
    }

    function getPlayerByAddress(address _addr,uint256 _rid) 
        public 
        view 
        returns(uint256 _plyrID,uint256 _uto,uint256 _price,uint256 _timestamp,bool _iswin)
    {
        require(_addr != address(0),"wallet is empty");
        uint256 plyid = pIDxAddr_[_addr];
        GuessDatasets.PlayerRounds storage plyrounds = plyrRnds_[plyid][_rid];
        return (plyrounds.plyrID,plyrounds.uto,plyrounds.price,plyrounds.timestamp,plyrounds.iswin);
    }

    function getActiveRounds()
        public  
        view
        returns (uint256[] memory _rids)
    {
        uint256[] memory  ridArr;
        if(roundID_ > pageSize_)
        {
            uint256 rid_count = roundID_.sub(pageSize_);
            ridArr = new uint256[](rid_count);
            for (uint256 i = 0; i < pageSize_; i++)
            {
                ridArr[i] = rid_count.add(i);
            }
        }
        else
        {
            ridArr = new uint256[](roundID_);
            for (uint256 j = 0; j < roundID_; j++)
            {
                ridArr[i] = j;
            }
        }
        return ridArr;
    }
}