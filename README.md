![GitHub Downloads (specific asset, latest release)](https://img.shields.io/github/downloads/CePeU/AssetPackSwitcher/latest/AssetPackSwitcher.zip)
![GitHub Downloads (specific asset, latest release)](https://img.shields.io/github/downloads/CePeU/AssetPackSwitcher/latest/AssetPackSwitcher_1.2.0.zip)

# What it does
This is a dungeondraft module based on uchideshi34(Jon) AssetSwap module.

It is so far also vibe coded but it works and does it job.   

It is an early version but it worked fine on two of my rather big maps.

As of version 1.1.0 you can also hash the assets of a pack and compare agains hashes/find corresponding assets according to their hash key.

The idea this module follows is to allow for you to switch your assets from one asset pack to using the assets of another asset pack. This can be exremly helpfull if a repack took place for any reason.   

So far the module compares the path and name of assets to find the corresponding assets in the each pack. If that is not sufficient you should try to use a hash but it might take a while (up to 5 - 10 minutes) to hash your selected pack. The hashes are stored in your dungeondraft user directory to be reused (or deleted manually by you if you do not need them anymore)

You can also bulk swap assets.

# Usage

You select a DESTINATION pack to which assets are switched to from the SOURCE pack. 

You select a SOURCE pack (these are the packs in your current map) and you can highlight all assets on that level (or collect all assets from every level) which belong to that pack by using the button "Find&Highlight".  

It will list them in the list field. Clicking on an asset or asset collection in the list field will zoom you to that asset or asset collection and highlight them.   

"Focus px" controls the zoom level. The selected assets view size will be scaled to this texture size (so standard is 256x256) and the viewport will be adjusted so that this view size is reached.

The first item will be blue. Clicking again will cycle trough that specific collection if there is more than one asset.   

Double click will select that asset for moving or manipulating it.   

To bulk switch asset you need to use the "Generate replacements button" to prepare a list of assets to be exchanged.   

The button "Execute generated replacements" will do the replace.   

It is highly recommendet to use "Find&Highlight" to get a feel what will happen.

The button "Add swap" will add a single item to the swap list (which is uchides mod) and the button "Add all to swap" will add all assets in the list to the swap list.   

Double entries will be removed.   

Be aware that the swap list is differentiated by type (doors, textures etc). You can open a tools menue after adding assets for swapping, select an asset there and when you tick on the feather scroll symbol that asset will be placed as a potentiel replacement in the list (you create a mapping).    

These items can be swapped with the button at the top with "Implement swap".   

I use this manual way of mapping items to do asset swaps that could not be done automatically (for example for assets that changed name) or which cannot be found by using hashes because they might have been dropped.   

Of course this also can be used to manually swap assets or bulk swap assets (like all chairs agains other chairs) but other mods like Moulks "Search and Replace" Mod might be equally or even better suited.

My mod will help you do manage your assets according to your packs.

