# Current successors after a genuine validator rotation

The existing signed slot12 crossing rotates pending validator Ed25519 ordering into active state.
Its exact selected parent/root feeds newly signed empty slot13 and slot14 children under the
maintained uniform fallback roster. A distinct same-epoch signing helper refuses any further
crossing; existing first-epoch helpers retain their old restriction. No marker is synthesized.

Independent phase composition defines expected physical maps, then separate candidate preparation
checks every successor, original aliases, prior commitment, exact parent, replay refusal and absent
chain finality. Literal slots and active/previous chapter bytes witness the rotation and its
preservation. Run `make unit SUITE=pvm_current_rotated_fixture`.
Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary. These authored witnesses
use the pinned release-reference backend, not current Thin VRF or independent complete STF goldens.
M1 framing and complete typed state serialization remain separate. No production policy changes.
