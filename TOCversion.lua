local _, _, _, tocversion = GetBuildInfo()
local TBC_ANNIVERSARY_VERSION = 20505

if tocversion ~= TBC_ANNIVERSARY_VERSION then
    -- Display error message to user
    local msg = string.format(
        "|cffff0000AutoConsume Error:|r This addon requires TBC Anniversary (version %d). Your version: %d. Addon will not load.",
        TBC_ANNIVERSARY_VERSION,
        tocversion
    )
    print(msg)
    return -- Stop execution
end