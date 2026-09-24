///|
/// One byte edge in the vocabulary prefix tree.
priv struct Edge {
  byte : Byte
  child : Int
}

///|
priv struct Node {
  edges : Array[Edge]
  ends : Array[Int]
}

///|
/// Tokens that share a byte prefix share a path. Empty tokens and the eos id are
/// left out, matching the full scan, which skips both.
priv struct Trie {
  nodes : Array[Node]
}

///|
fn Trie::build(vocab : @vocab.Vocab) -> Trie {
  let nodes : Array[Node] = [{ edges: [], ends: [], }]
  for id in 0..<vocab.size() {
    if id == vocab.eos {
      continue
    }
    let bytes = vocab.tokens[id]
    if bytes.length() == 0 {
      continue
    }
    let mut n = 0
    for byte in bytes {
      let mut child = -1
      let edges = nodes[n].edges
      for i in 0..<edges.length() {
        if edges[i].byte == byte {
          child = edges[i].child
          break
        }
      }
      if child < 0 {
        child = nodes.length()
        nodes[n].edges.push({ byte, child, })
        nodes.push({ edges: [], ends: [], })
      }
      n = child
    }
    nodes[n].ends.push(id)
  }
  { nodes, }
}

///|
/// Tokens whose bytes survive `dfa` from `state`, in increasing token id order.
/// A dead prefix drops the whole subtree. The id order matches a scan that tries
/// every token once.
fn Trie::collect(
  self : Trie,
  dfa : @regex.Dfa,
  state : Int,
) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let stack : Array[(Int, Int)] = [(0, state)]
  let mut pending = true
  while pending {
    match stack.pop() {
      None => pending = false
      Some((node, ds)) => {
        let here = self.nodes[node]
        for id in here.ends {
          out.push((id, ds))
        }
        for edge in here.edges {
          let next = dfa.step(ds, edge.byte)
          if next >= 0 {
            stack.push((edge.child, next))
          }
        }
      }
    }
  }
  out.sort_by_key(fn(pair) { pair.0 })
  out
}
