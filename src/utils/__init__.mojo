"""Small helpers shared across the runtime."""

from .memory import alloc_one, free_one, unsafe_arc_take
from .erased_owned_pointer import ErasedOwnedPointer, TypeMismatchError
from .type_id import TypeId
