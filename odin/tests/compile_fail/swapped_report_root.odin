// A package identity cannot be initialized with an exported-segment commitment.
package main
import codec "../../codec"
// This trusted negative fixture deliberately violates nominal report-hash domains.
main :: proc() {
	wrong := codec.Report_Header {
		package_hash = codec.Segment_Root{},
	}
	_ = wrong
}
