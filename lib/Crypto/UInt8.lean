namespace UInt8

def digitChar (n : UInt8) : Char :=
  if n = 0 then '0' else
  if n = 1 then '1' else
  if n = 2 then '2' else
  if n = 3 then '3' else
  if n = 4 then '4' else
  if n = 5 then '5' else
  if n = 6 then '6' else
  if n = 7 then '7' else
  if n = 8 then '8' else
  if n = 9 then '9' else
  if n = 0xa then 'A' else
  if n = 0xb then 'B' else
  if n = 0xc then 'C' else
  if n = 0xd then 'D' else
  if n = 0xe then 'E' else
  if n = 0xf then 'F' else
  '*'


def toHex (c : UInt8) : String :=
  String.singleton (digitChar (c / 16)) ++ String.singleton (digitChar (c % 16))

end UInt8