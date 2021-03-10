import "../../lib/SafeERC20.sol";
import "../../lib/SafeMath.sol";
import "../../lib/IUniswapV2Pair.sol";
import "../../lib/UniswapV2OracleLibrary.sol";

// Hardcoding a lot of constants and stripping out unnecessary things because of high gas prices
contract TWAPBoundedUSTONKSAPR {
    using SafeMath for uint256;

    uint256 internal constant BASE = 10**18;

    uint256 internal constant ONE = 10**18;

    /// @notice Current uniswap pair for purchase & sale tokens
    UniswapPair internal uniswap_pair =
        UniswapPair(0xEdf187890Af846bd59f560827EBD2091C49b75Df);

    IERC20 internal constant USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    IERC20 internal constant USTONKS_APR =
        IERC20(0xEC58d3aefc9AAa2E0036FA65F70d569f49D9d1ED);

    /// @notice last cumulative price update time
    uint32 internal block_timestamp_last;

    /// @notice last cumulative price;
    uint256 internal price_cumulative_last;

    /// @notice Minimum amount of time since TWAP set
    uint256 internal constant MIN_TWAP_TIME = 60 * 60; // 1 hour

    /// @notice Maximum amount of time since TWAP set
    uint256 internal constant MAX_TWAP_TIME = 120 * 60; // 2 hours

    /// @notice % bound away from TWAP price
    uint256 internal constant TWAP_BOUNDS = 5 * 10**15;

    function quote(uint256 purchaseAmount, uint256 saleAmount)
        internal
        view
        returns (uint256)
    {
        return purchaseAmount.mul(ONE).div(saleAmount);
    }

    function bounds(uint256 uniswap_quote) internal view returns (uint256) {
        uint256 minimum = uniswap_quote.mul(BASE.sub(TWAP_BOUNDS)).div(BASE);
        return minimum;
    }

    function bounds_max(uint256 uniswap_quote) internal view returns (uint256) {
        uint256 maximum = uniswap_quote.mul(BASE.add(TWAP_BOUNDS)).div(BASE);
        return maximum;
    }


    function withinBounds(uint256 purchaseAmount, uint256 saleAmount)
        internal
        
        returns (bool)
    {
        uint256 uniswap_quote = consult();
        uint256 quoted = quote(purchaseAmount, saleAmount);
        uint256 minimum = bounds(uniswap_quote);
        uint256 maximum = bounds_max(uniswap_quote);

        return quoted > minimum && quoted < maximum;
    }

    // callable by anyone
    function update_twap() public {
        (uint256 sell_token_priceCumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(
                address(uniswap_pair),
                false
            );
        uint32 timeElapsed = blockTimestamp - block_timestamp_last; // overflow is impossible

        // ensure that it's been long enough since the last update
        require(timeElapsed >= MIN_TWAP_TIME, "OTC: MIN_TWAP_TIME NOT ELAPSED");

        price_cumulative_last = sell_token_priceCumulative;

        block_timestamp_last = blockTimestamp;
    }

    function consult() internal view returns (uint256) {
        (uint256 sell_token_priceCumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(
                address(uniswap_pair),
                false
            );
        uint32 timeElapsed = blockTimestamp - block_timestamp_last; // overflow is impossible

        // overflow is desired
        uint256 priceAverageSell =
            uint256(
                uint224(
                    (sell_token_priceCumulative - price_cumulative_last) /
                        timeElapsed
                )
            );

        // single hop
        uint256 purchasePrice;
        if (priceAverageSell > uint192(-1)) {
            // eat loss of precision
            // effectively: (x / 2**112) * 1e18
            purchasePrice = (priceAverageSell >> 112) * ONE;
        } else {
            // cant overflow
            // effectively: (x * 1e18 / 2**112)
            purchasePrice = (priceAverageSell * ONE) >> 112;
        }
        return purchasePrice;
    }

    modifier timeBoundsCheck() {
        uint256 elapsed_since_update = block.timestamp - block_timestamp_last;
        require(
            block.timestamp - block_timestamp_last < MAX_TWAP_TIME,
            "Cumulative price snapshot too old"
        );
        require(
            block.timestamp - block_timestamp_last > MIN_TWAP_TIME,
            "Cumulative price snapshot too new"
        );
        _;
    }
}
