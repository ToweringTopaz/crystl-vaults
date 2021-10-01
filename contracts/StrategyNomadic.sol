// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./libs/IMasterchef.sol";
import "./BaseStrategyLP.sol";
import "./libs/ITactic.sol";
import "./VaultHealer.sol";

contract StrategyNomadic is BaseStrategyLP {
    using Address for address;

    struct NomadMigration {
        
        ITactic tactic;
        address router;
        address masterchef;
        uint pid;
        uint readyTime;
        uint slippage;
        address[8] earned;
        uint earnedLength;
    }

    uint constant public MIGRATION_TIMELOCK = 600; //TODO: increase after testing
    
    uint pid;
    address public khan;
    ITactic tactic;
    address[][] preparedPaths;
    
    NomadMigration public plannedMigration;
    
    event NewKhan(address indexed _khan);
    event MigrationPlan(NomadMigration indexed migration);

    constructor(
        Addresses memory _addresses,
        Settings memory _settings,
        address[][] memory _paths,  //need paths for earned to each of (wmatic, dai, crystl, token0, token1): 5 total
        uint256 _pid,
        ITactic _tactic
    ) BaseStrategy(_addresses, _settings, _paths) {
        
        addresses.lpToken[0] = IUniPair(_addresses.want).token0();
        addresses.lpToken[1] = IUniPair(_addresses.want).token1();
        
        pid = _pid;
        khan = msg.sender;
        tactic = _tactic;
    }

    modifier onlyGov() override {
        require(msg.sender == Ownable(addresses.vaulthealer).owner() || msg.sender == khan, "!gov");
        _;
    }
    function setKhan(address _khan) external onlyGov {
        khan = _khan;
        emit NewKhan(_khan);
    }
    
    function planMigration(address _tactic, address _router, address _masterchef, uint _pid, uint _slippage, address[] calldata _earned) external onlyGov {
        require(_tactic.isContract(), "invalid tactic");
        require(_router.isContract() && IUniRouter02(_router).factory() != address(0), "invalid router");
        require(_masterchef.isContract(), "invalid masterchef");
        require(_slippage < SLIPPAGE_FACTOR_UL, "invalid slippage");
        
        plannedMigration.tactic = ITactic(_tactic);
        plannedMigration.router = _router;
        plannedMigration.masterchef = _masterchef;
        plannedMigration.pid = _pid;
        plannedMigration.readyTime = block.timestamp + MIGRATION_TIMELOCK;
        plannedMigration.slippage = _slippage;
        
        uint _earnedLength;
        uint i;
        for (; i < _earned.length; i++) {
            if (_earned[i] == address(0)) break;
            plannedMigration.earned[i] = _earned[i];
            _earnedLength++;
        }
        require(_earnedLength > 0 && _earnedLength <= 8, "invalid _earned");
        plannedMigration.earnedLength = _earnedLength;
        for (; i < plannedMigration.earned.length; i++) {
            plannedMigration.earned[i] = address(0);
        }
    }
    
    function cancelMigration() external onlyGov {
        delete plannedMigration;
        emit MigrationPlan(plannedMigration);
    }
    
    function executeMigration() external onlyGov {
        require(address(plannedMigration.tactic) != address(0), "no planned migration");
        require(block.timestamp >= plannedMigration.readyTime, "migration not ready");
        //compound first
        _earn(msg.sender);
        
        //pull everything out
        uint vaultSharesBefore = vaultSharesTotal();
        uint wantLockedBefore = vaultSharesBefore + wantBalance();
        _vaultWithdraw(vaultSharesBefore);
        uint vaultSharesAfter = vaultSharesTotal();
        if (vaultSharesAfter > 0) {
            _emergencyVaultWithdraw();
        }
        settings.slippageFactor = plannedMigration.slippage;
        
        if (plannedMigration.router != addresses.router) {
            IUniRouter02(addresses.router).removeLiquidity(
                addresses.lpToken[0],
                addresses.lpToken[1],
                IERC20(addresses.want).balanceOf(address(this)),
                0,
                0,
                address(this),
                block.timestamp
            );
        }
        for (uint i; i < preparedPaths.length; i++) {
            _setPath(preparedPaths[i]);
        }
        while (preparedPaths.length > 0) {
            preparedPaths.pop();
        }
        if (plannedMigration.router != addresses.router) {
            addresses.router = plannedMigration.router;
            
            address factory = IUniRouter02(addresses.router).factory();
            addresses.want = IUniFactory(factory).getPair(addresses.lpToken[0], addresses.lpToken[1]);
            PrismLibrary2.optimalMint(addresses.want, addresses.lpToken[0], addresses.lpToken[1]);
        }
        
        addresses.masterchef = plannedMigration.masterchef;
        pid = plannedMigration.pid;
        addresses.earned = plannedMigration.earned;
        tactic = plannedMigration.tactic;
        _farm();
        uint wantLockedAfter = wantLockedTotal();
        require(wantLockedAfter > wantLockedBefore * settings.slippageFactor**2 / 1e8, "migration slippage too high");
        VaultHealer(addresses.vaulthealer).strategyWantMigration(IUniPair(addresses.want));
    }
    
    
    
    function preparePath(address[] calldata _path) external onlyGov {
        preparedPaths.push() = _path;
    }

    function _vaultDeposit(uint256 _amount) internal virtual override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultDeposit.selector, addresses.masterchef, pid, _amount
        ), "vaultdeposit failed");
    }
    
    function _vaultWithdraw(uint256 _amount) internal virtual override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultWithdraw.selector, addresses.masterchef, pid, _amount
        ), "vaultwithdraw failed");
    }
    
    function _vaultHarvest() internal virtual override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._vaultHarvest.selector, addresses.masterchef, pid
        ), "vaultharvest failed");
    }
    
    function vaultSharesTotal() public virtual override view returns (uint256) {
        return tactic.vaultSharesTotal(addresses.masterchef, pid, address(this));
    }
    
    function _emergencyVaultWithdraw() internal virtual override {
        address(tactic).functionDelegateCall(abi.encodeWithSelector(
            tactic._emergencyVaultWithdraw.selector, addresses.masterchef, pid
        ), "emergencyvaultwithdraw failed");
    }
}