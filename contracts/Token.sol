pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
  // ------------------------------------------ //
  // ----- BEGIN: DO NOT EDIT THIS SECTION ---- //
  // ------------------------------------------ //
  using SafeMath for uint256;
  uint256 public totalSupply;
  uint256 public decimals = 18;
  string public name = "Test token";
  string public symbol = "TEST";
  mapping (address => uint256) public balanceOf;
  // ------------------------------------------ //
  // ----- END: DO NOT EDIT THIS SECTION ------ //  
  // ------------------------------------------ //

  // ERC20 allowance mapping: owner => spender => amount
  mapping(address => mapping(address => uint256)) private allowances;

  // Efficient holder tracking for dividend distribution
  address[] private tokenHolders;
  mapping(address => uint256) private holderIndex; // 1-based index, 0 means not in list

  // Track withdrawable dividends per address
  mapping(address => uint256) private withdrawableDividends;

  /**
   * @dev Add a holder to the list if they have a non-zero balance
   * Uses 1-based indexing to distinguish between "not in list" (0) and "first element" (1)
   */
  function _addHolder(address holder) private {
    if (holderIndex[holder] == 0 && balanceOf[holder] > 0) {
      tokenHolders.push(holder);
      holderIndex[holder] = tokenHolders.length;
    }
  }

  /**
   * @dev Remove a holder from the list when their balance reaches zero
   * Uses swap-and-pop pattern for O(1) removal
   */
  function _removeHolder(address holder) private {
    uint256 index = holderIndex[holder];
    if (index != 0 && balanceOf[holder] == 0) {
      uint256 lastIndex = tokenHolders.length;
      // Swap with last element if not already last
      if (index != lastIndex) {
        address lastHolder = tokenHolders[lastIndex - 1];
        tokenHolders[index - 1] = lastHolder;
        holderIndex[lastHolder] = index;
      }
      tokenHolders.pop();
      holderIndex[holder] = 0;
    }
  }

  /**
   * @dev Update holder list after a balance change
   * Adds holder if balance becomes non-zero, removes if balance becomes zero
   */
  function _updateHolder(address holder) private {
    if (balanceOf[holder] > 0) {
      _addHolder(holder);
    } else {
      _removeHolder(holder);
    }
  }

  // IERC20

  function allowance(address owner, address spender) external view override returns (uint256) {
    return allowances[owner][spender];
  }

  function transfer(address to, uint256 value) external override returns (bool) {
    require(to != address(0), "Transfer to zero address");
    require(balanceOf[msg.sender] >= value, "Insufficient balance");

    balanceOf[msg.sender] = balanceOf[msg.sender].sub(value);
    balanceOf[to] = balanceOf[to].add(value);

    // Update holder tracking for both addresses
    _updateHolder(msg.sender);
    _updateHolder(to);

    return true;
  }

  function approve(address spender, uint256 value) external override returns (bool) {
    allowances[msg.sender][spender] = value;
    return true;
  }

  function transferFrom(address from, address to, uint256 value) external override returns (bool) {
    require(to != address(0), "Transfer to zero address");
    require(balanceOf[from] >= value, "Insufficient balance");
    require(allowances[from][msg.sender] >= value, "Insufficient allowance");

    balanceOf[from] = balanceOf[from].sub(value);
    balanceOf[to] = balanceOf[to].add(value);
    allowances[from][msg.sender] = allowances[from][msg.sender].sub(value);

    // Update holder tracking for both addresses
    _updateHolder(from);
    _updateHolder(to);

    return true;
  }

  // IMintableToken

  function mint() external payable override {
    require(msg.value > 0, "Must send ETH to mint");

    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
    totalSupply = totalSupply.add(msg.value);

    _addHolder(msg.sender);
  }

  function burn(address payable dest) external override {
    require(balanceOf[msg.sender] > 0, "No tokens to burn");
    require(dest != address(0), "Invalid destination address");

    uint256 amount = balanceOf[msg.sender];
    balanceOf[msg.sender] = 0;
    totalSupply = totalSupply.sub(amount);

    _removeHolder(msg.sender);

    dest.transfer(amount);
  }

  // IDividends

  function getNumTokenHolders() external view override returns (uint256) {
    return tokenHolders.length;
  }

  function getTokenHolder(uint256 index) external view override returns (address) {
    require(index >= 1 && index <= tokenHolders.length, "Index out of bounds");
    return tokenHolders[index - 1];
  }

  function recordDividend() external payable override {
    require(msg.value > 0, "Must send ETH to record dividend");
    require(totalSupply > 0, "No token holders to distribute dividend");

    // Distribute dividend proportionally to all current token holders
    // Each holder receives a share based on their token balance relative to total supply
    for (uint256 i = 0; i < tokenHolders.length; i++) {
      address holder = tokenHolders[i];
      uint256 holderBalance = balanceOf[holder];
      // 10 * 1 / 100 = 0.1
      // Calculate proportional share: (holderBalance * msg.value) / totalSupply
      uint256 dividendShare = holderBalance.mul(msg.value).div(totalSupply);
      withdrawableDividends[holder] = withdrawableDividends[holder].add(dividendShare);
    }
  }

  function getWithdrawableDividend(address payee) external view override returns (uint256) {
    return withdrawableDividends[payee];
  }

  function withdrawDividend(address payable dest) external override {
    require(dest != address(0), "Invalid destination address");
    
    uint256 amount = withdrawableDividends[msg.sender];
    require(amount > 0, "No dividend to withdraw");

    // Reset withdrawable balance before transfer to prevent reentrancy
    withdrawableDividends[msg.sender] = 0;
    dest.transfer(amount);
  }
}