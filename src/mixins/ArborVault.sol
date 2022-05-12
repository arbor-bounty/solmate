import {ERC4626} from "./ERC4626.sol";
import {Pool} from "https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/pool/Pool.sol";

contract ArborVault is ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    address constant USDC_ADDRESS = 0x02444D214962eC73ab733bB00Ca98879efAAa73d;
    ERC20 constant USDC_CONTRACT = ERC20(USDC_ADDRESS);

    address constant AAVE_POOL_ADDRESS = 0xC4744c984975ab7d41e0dF4B37E048Ef8006115E;
    Pool constant AAVE_POOL = Pool(AAVE_POOL_ADDRESS);

    constructor() ERC4626(USDC_CONTRACT, "Vault Shares", "VASH") {}

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    // ~20% of deposited USDC held in vault
    function reserve_assets() public view returns (uint256) {
        return USDC_CONTRACT.balanceOf(address(this));
    }

    // ~80% of deposited USDC supplied to AAVE
    function collateral_assets() public view returns (uint256) {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = AAVE_POOL.getUserAccountData(address(this));

        return totalCollateralBase / 100;
    }

    function totalAssets() public view override returns (uint256) {
        return reserve_assets() + collateral_assets();
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint original_return = supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());

        return assets < reserve_assets() ? original_return : reserve_assets();
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return previewWithdraw(convertToAssets(shares));
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function check_ratio() internal {

        uint current_reserve = reserve_assets();
        uint collateral_base = collateral_assets();
        uint total_usdc = totalAssets();

        uint percent_reserve = current_reserve * 100 / total_usdc;

        // want reserve ratio to be 20%
        uint desired_reserve = total_usdc / 5;
        if (percent_reserve < 15) {
            uint withdraw_amount = desired_reserve - current_reserve;
            AAVE_POOL.withdraw(USDC_ADDRESS, withdraw_amount, address(this));
        }
        else if (percent_reserve > 25) {
            uint deposit_amount = current_reserve - desired_reserve;
            USDC_CONTRACT.approve(AAVE_POOL_ADDRESS, deposit_amount);
            AAVE_POOL.supply(USDC_ADDRESS, deposit_amount, address(this), 0);
        }
    }

    function deposit(uint assets) public {
        deposit(assets, msg.sender);

        check_ratio();
    }

    function withdraw(uint assets) public {
        withdraw(assets, msg.sender, msg.sender);

        check_ratio();
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    // quoted in usdc
    function maxDeposit(address owner) public view override returns (uint256) {
        return USDC_CONTRACT.balanceOf(owner);
    }

    // quoted in shares
    function maxMint(address owner) public view override returns (uint256) {
        return convertToShares(maxDeposit(owner));
    }

    function min(uint x, uint y) internal view returns (uint) {
        return x < y ? x : y;
    }

    // quoted in usdc
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint owner_assets = convertToAssets(balanceOf[owner]);
        return min(owner_assets, reserve_assets());
    }

    // quoted in shares
    function maxRedeem(address owner) public view override returns (uint256) {
        return convertToShares(maxWithdraw(owner));
    }
}