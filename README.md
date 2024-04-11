# Infernal Rift

Proof of concept NFT bridge w/ additional conveniences (batch bridging, deterministic addresses, clones, royalties, and custom tokenURI).

### General Design

#### L1 --> L2

`InfernalRiftAbove` lives on L1 and sends messages directly to the `OptimismPortal`. This is intended to reduce gas costs (e.g. no SSTORE needed to store nonces). It iterates through all NFTs desired to bridge, grabs the tokenURI / royalty info, and sends that off to the Portal as a payload.

NFTs are then locked up in the RiftAbove.

`InfernalRiftBelow` lives on L2 and receives messages. Upon receiving a payload, it checks to see if the NFT already exists on L2. If so, then it means it has been locked up and is owned by the RiftBelow, so it just sends to the receiver. Otherwise, it'll deploy a new instance of `ERC721Bridgable` and set the corresponding tokenURI and royalty values. It then mints to the recipient.

#### L2 --> L1 (WIP)

`InfernalRiftBelow` messages the `L2CrossDomainMessenger` with the NFTs to bridge as well as the recipient. The L2 NFT is locked up in the RiftBelow.

(figure out how to finalize on L1 and then finish claim on L1, minimize gas needed if possible)

### Claiming Royalties (WIP)

Finalize royalty retrieval design pattern (e.g. either withdraw to L1 or have authorized call to RiftBelow that can wihdraw to L2)