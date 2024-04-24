// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;
pragma abicoder v2;

interface IOwnable {
    function owner() external view returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner_) external;
}

contract Ownable is IOwnable {
    address internal _owner;
    address internal _newOwner;

    event OwnershipPushed(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _owner = msg.sender;
        emit OwnershipPushed(address(0), _owner);
    }

    function owner() public view override returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual override onlyOwner {
        emit OwnershipPushed(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(
        address newOwner_
    ) public virtual override onlyOwner {
        require(
            newOwner_ != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipPushed(_owner, newOwner_);
        _owner = newOwner_;
    }
}

contract VaultOwned is Ownable {
    address internal _vault;

    function setVault(address vault_) external onlyOwner returns (bool) {
        _vault = vault_;

        return true;
    }

    function vault() public view returns (address) {
        return _vault;
    }

    modifier onlyVault() {
        require(_vault == msg.sender, "VaultOwned: caller is not the Vault");
        _;
    }
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }

    function sqrrt(uint256 a) internal pure returns (uint256 c) {
        if (a > 3) {
            c = a;
            uint256 b = add(div(a, 2), 1);
            while (b < c) {
                c = b;
                b = div(add(div(a, b), b), 2);
            }
        } else if (a != 0) {
            c = 1;
        }
    }
}

library Math {
    function min(uint x, uint y) internal pure returns (uint z) {
        z = x < y ? x : y;
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }

    function functionCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return
            functionCallWithValue(
                target,
                data,
                value,
                "Address: low-level call with value failed"
            );
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(
            address(this).balance >= value,
            "Address: insufficient balance for call"
        );
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{value: value}(
            data
        );
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _functionCallWithValue(
        address target,
        bytes memory data,
        uint256 weiValue,
        string memory errorMessage
    ) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{value: weiValue}(
            data
        );
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }

    function functionStaticCall(
        address target,
        bytes memory data
    ) internal view returns (bytes memory) {
        return
            functionStaticCall(
                target,
                data,
                "Address: low-level static call failed"
            );
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function functionDelegateCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory) {
        return
            functionDelegateCall(
                target,
                data,
                "Address: low-level delegate call failed"
            );
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }

    function addressToString(
        address _address
    ) internal pure returns (string memory) {
        bytes32 _bytes = bytes32(uint256(_address));
        bytes memory HEX = "0123456789abcdef";
        bytes memory _addr = new bytes(42);

        _addr[0] = "0";
        _addr[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            _addr[2 + i * 2] = HEX[uint8(_bytes[i + 12] >> 4)];
            _addr[3 + i * 2] = HEX[uint8(_bytes[i + 12] & 0x0f)];
        }

        return string(_addr);
    }
}

interface IERC20 {
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

abstract contract ERC20 is IERC20 {
    using SafeMath for uint256;

    // TODO comment actual hash value.
    bytes32 private constant ERC20TOKEN_ERC1820_INTERFACE_ID =
        keccak256("ERC20Token");

    mapping(address => uint256) internal _balances;

    mapping(address => mapping(address => uint256)) internal _allowances;

    uint256 internal _totalSupply;

    string internal _name;

    string internal _symbol;

    uint8 internal _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            msg.sender,
            _allowances[sender][msg.sender].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public virtual returns (bool) {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public virtual returns (bool) {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(
            amount,
            "ERC20: transfer amount exceeds balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account_, uint256 ammount_) internal virtual {
        require(account_ != address(0), "ERC20: mint to the zero address");
        _beforeTokenTransfer(address(this), account_, ammount_);
        _totalSupply = _totalSupply.add(ammount_);
        _balances[account_] = _balances[account_].add(ammount_);
        emit Transfer(address(this), account_, ammount_);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(
            amount,
            "ERC20: burn amount exceeds balance"
        );
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(
        address from_,
        address to_,
        uint256 amount_
    ) internal virtual {}
}

interface IERC2612Permit {
    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(address owner) external view returns (uint256);
}

library Counters {
    using SafeMath for uint256;

    struct Counter {
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        counter._value += 1;
    }

    function decrement(Counter storage counter) internal {
        counter._value = counter._value.sub(1);
    }
}

abstract contract ERC20Permit is ERC20, IERC2612Permit {
    using Counters for Counters.Counter;

    mapping(address => Counters.Counter) private _nonces;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    bytes32 public DOMAIN_SEPARATOR;

    constructor() {
        uint256 chainID;
        assembly {
            chainID := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name())),
                keccak256(bytes("1")), // Version
                chainID,
                address(this)
            )
        );
    }

    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        require(block.timestamp <= deadline, "Permit: expired deadline");

        bytes32 hashStruct = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                amount,
                _nonces[owner].current(),
                deadline
            )
        );

        bytes32 _hash = keccak256(
            abi.encodePacked(uint16(0x1901), DOMAIN_SEPARATOR, hashStruct)
        );

        address signer = ecrecover(_hash, v, r, s);
        require(
            signer != address(0) && signer == owner,
            "ZeroSwapPermit: Invalid signature"
        );

        _nonces[owner].increment();
        _approve(owner, spender, amount);
    }

    function nonces(address owner) public view override returns (uint256) {
        return _nonces[owner].current();
    }
}

library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(
            value
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(
            value,
            "SafeERC20: decreased allowance below zero"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        bytes memory returndata = address(token).functionCall(
            data,
            "SafeERC20: low-level call failed"
        );
        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }
}

library FullMath {
    function fullMul(
        uint256 x,
        uint256 y
    ) private pure returns (uint256 l, uint256 h) {
        uint256 mm = mulmod(x, y, uint256(-1));
        l = x * y;
        h = mm - l;
        if (mm < l) h -= 1;
    }

    function fullDiv(
        uint256 l,
        uint256 h,
        uint256 d
    ) private pure returns (uint256) {
        uint256 pow2 = d & -d;
        d /= pow2;
        l /= pow2;
        l += h * ((-pow2) / pow2 + 1);
        uint256 r = 1;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        return l * r;
    }

    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256) {
        (uint256 l, uint256 h) = fullMul(x, y);
        uint256 mm = mulmod(x, y, d);
        if (mm > l) h -= 1;
        l -= mm;
        require(h < d, "FullMath::mulDiv: overflow");
        return fullDiv(l, h, d);
    }
}

interface IUniswapV2Pair {
    function balanceOf(address owner) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);

    function transfer(address to, uint value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint value
    ) external returns (bool);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function totalSupply() external view returns (uint256);
}

interface ISwapV2Router {
    function factory() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

interface ILpManager {
    function addLiquidityNoUpdate(
        address _token,
        uint256 _amount,
        uint256 _minPlp,
        address _receipt
    ) external payable;
}

interface IPID {
    function inviterRebatesValue(
        address _account,
        uint256 _value
    ) external view returns (address, uint256);
}

contract DYNABondDepository is VaultOwned {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public immutable PID;
    address public immutable USDC;
    address public immutable DYNA;
    address public immutable esDYNA;
    address public immutable pair; //DYNA-USDC
    address public immutable treasury;
    address public immutable LpManager;
    ISwapV2Router public immutable router;

    uint256 public lastTxTimestamp; // last buy bond time

    uint256 public amountPRECISION = 1000 * 1e18;
    uint256 public timePRECISION = 1000;
    uint256 public constant priceDecimals = 1e8;
    uint256 public rateMinutes = 4 * 60;
    uint256 public basicDiscountRate = 20; //basic Rate
    uint256 public maxtRate = 80000; //max Rate
    uint256 public minRate = 20000; //min Rate

    mapping(uint256 => uint256) public bougntAmout; // minute => buy bond amount USDC

    mapping(address => uint256) public inviterRebates; // inviter address => reward

    Term public terms;

    struct Term {
        uint256 minPayout;
        uint256 maxPayout;
        uint256 maxDebt;
        uint256 saleDebt;
        bool status;
    }

    // simple re-entrancy check
    uint internal _unlocked = 1;

    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    event Deposit(
        address indexed sender,
        address indexed to,
        uint256 inputAmount,
        uint256 payoutValue,
        uint256 timestamp
    );

    event ClaimRebates(
        address indexed sender,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    constructor(
        address _USDC,
        address _DYNA,
        address _esDYNA,
        address _pair,
        address _router,
        address _treasury,
        address _lpManager,
        address _PID
    ) {
        PID = _PID;
        USDC = _USDC;
        DYNA = _DYNA;
        esDYNA = _esDYNA;
        pair = _pair;
        router = ISwapV2Router(_router);
        LpManager = _lpManager;
        treasury = _treasury;
        lastTxTimestamp = block.timestamp;
        IERC20(_USDC).approve(address(_router), uint256(-1));
        IERC20(_USDC).approve(address(_lpManager), uint256(-1));
        IERC20(_DYNA).approve(address(_router), uint256(-1));
        terms.status = true;
    }

    function setRateParams(
        uint256 _minutes,
        uint256 _basic,
        uint256 _min,
        uint256 _max
    ) external onlyOwner {
        rateMinutes = _minutes;
        basicDiscountRate = _basic;
        maxtRate = _max;
        minRate = _min;
    }

    function setBondTerms(
        uint256 _min,
        uint256 _max,
        uint256 _maxDebt,
        uint256 _saleDebt,
        bool _status
    ) external onlyOwner {
        terms = Term({
            minPayout: _min,
            maxPayout: _max,
            maxDebt: _maxDebt,
            saleDebt: _saleDebt,
            status: _status
        });
    }

    function deposit(uint256 amount, address _depositor) external lock {
        require(terms.status, "not open");

        terms.saleDebt += amount;
        // cal payout
        uint256 payoutValue = payout(amount);
        //cal rebates
        (address inviter, uint256 rebatesValue) = IPID(PID).inviterRebatesValue(
            msg.sender,
            payoutValue//amount
        );
        inviterRebates[inviter] += calDecimals(rebatesValue);

        lastTxTimestamp = block.timestamp;
        uint cur_c = block.timestamp / 60;
        bougntAmout[cur_c] += amount;

        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);

        //send esDYNA to depositor
        IERC20(esDYNA).safeTransfer(_depositor, payoutValue);

        //add plp
        ILpManager(LpManager).addLiquidityNoUpdate(
            USDC,
            IERC20(USDC).balanceOf(address(this)).div(2),
            0,
            treasury
        );

        // addLiquidity
        uint256 DYNAAmount = calAndSwap();
        router.addLiquidity(
            USDC,
            DYNA,
            IERC20(USDC).balanceOf(address(this)),
            DYNAAmount,
            0,
            0,
            treasury,
            block.timestamp
        );

        emit Deposit(
            msg.sender,
            _depositor,
            amount,
            payoutValue,
            block.timestamp
        );
    }

    function claimBondRebates(address account) external lock {
        uint rewards = inviterRebates[account];
        inviterRebates[account] = 0;
        IERC20(esDYNA).safeTransfer(account, rewards);

        emit ClaimRebates(msg.sender, account, rewards, block.timestamp);
    }

    function payout(uint256 amount) public view returns (uint256) {
        uint calAmount = calDecimals(amount);
        return
            calAmount
                .mul(priceDecimals)
                .mul(1e5)
                .div(1e5 - DiscountRate())
                .div(getPrice());
    }

    function calDecimals(uint256 amount) public view returns (uint256) {
        uint USDCDecimals = IERC20(USDC).decimals();
        uint esDYNADecimals = IERC20(esDYNA).decimals();
        return amount.mul(10 ** esDYNADecimals).div(10 ** USDCDecimals); //
    }

    function DiscountRate() public view returns (uint256 rate) {
        rate = basicDiscountRate.mul(
            1000 -
                countBought().div(amountPRECISION) +
                (block.timestamp - lastTxTimestamp) /
                timePRECISION
        );
        if (rate > maxtRate) {
            rate = maxtRate;
        }
        if (rate < minRate) {
            rate = minRate;
        }
    }

    function countBought() public view returns (uint256) {
        uint256 amount = 0;
        uint cur_c = block.timestamp / 60;
        for (uint i = 0; i < rateMinutes; i++) {
            amount += bougntAmout[cur_c - i];
        }
        return amount;
    }

    function getPrice() public view returns (uint _price) {
        uint token0 = IERC20(IUniswapV2Pair(pair).token0()).decimals();
        uint token1 = IERC20(IUniswapV2Pair(pair).token1()).decimals();
        (uint reserve0, uint reserve1, ) = IUniswapV2Pair(pair).getReserves();
        uint decimals = 1;

        if (IUniswapV2Pair(pair).token0() == DYNA) {
            if (token0 > token1) {
                decimals = token0.sub(token1);
                _price = reserve1.mul(10 ** decimals).mul(priceDecimals).div(
                    reserve0
                );
            } else if (token1 > token0) {
                decimals = token1.sub(token0);
                _price = reserve1.mul(priceDecimals).div(
                    reserve0.mul(10 ** decimals)
                );
            } else {
                _price = reserve1.mul(priceDecimals).div(reserve0);
            }
        } else {
            if (token0 > token1) {
                decimals = token0.sub(token1);
                _price = reserve0.mul(priceDecimals).div(
                    reserve1.mul(10 ** decimals)
                );
            } else if (token1 > token0) {
                decimals = token1.sub(token0);
                _price = reserve0.mul(10 ** decimals).mul(priceDecimals).div(
                    reserve1
                );
            } else {
                _price = reserve0.mul(priceDecimals).div(reserve1);
            }
        }
    }

    function calAndSwap() public returns (uint256 DYNAAmount) {
        IUniswapV2Pair lpToken = IUniswapV2Pair(pair);
        (uint256 token0Reserve, uint256 token1Reserve, ) = lpToken
            .getReserves();
        (uint256 debtReserve, uint256 relativeReserve) = USDC ==
            lpToken.token0()
            ? (token0Reserve, token1Reserve)
            : (token1Reserve, token0Reserve);
        (uint256 swapAmt, bool isReversed) = optimalDeposit(
            IERC20(USDC).balanceOf(address(this)),
            0,
            debtReserve,
            relativeReserve
        );

        if (swapAmt > 0) {
            address[] memory path = new address[](2);
            (path[0], path[1]) = isReversed ? (DYNA, USDC) : (USDC, DYNA);
            uint[] memory amounts = router.swapExactTokensForTokens(
                swapAmt,
                0,
                path,
                address(this),
                block.timestamp
            );
            DYNAAmount = amounts[1];
        }
    }

    function optimalDeposit(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) internal pure returns (uint256 swapAmt, bool isReversed) {
        if (amtA.mul(resB) >= amtB.mul(resA)) {
            swapAmt = _optimalDepositA(amtA, amtB, resA, resB);
            isReversed = false;
        } else {
            swapAmt = _optimalDepositA(amtB, amtA, resB, resA);
            isReversed = true;
        }
    }

    function _optimalDepositA(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) internal pure returns (uint256) {
        require(amtA.mul(resB) >= amtB.mul(resA), "Reversed");

        uint256 a = 997;
        uint256 b = uint256(1997).mul(resA);
        uint256 _c = (amtA.mul(resB)).sub(amtB.mul(resA));
        uint256 c = _c.mul(1000).div(amtB.add(resB)).mul(resA);

        uint256 d = a.mul(c).mul(4);
        uint256 e = Math.sqrt(b.mul(b).add(d));

        uint256 numerator = e.sub(b);
        uint256 _denominator = a.mul(2);

        return numerator.div(_denominator);
    }
}
