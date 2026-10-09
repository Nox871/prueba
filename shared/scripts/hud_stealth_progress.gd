# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
extends PanelContainer

const ITEM_SLOT: PackedScene = preload("uid://1mjm4atk2j6e")
## Cada hilo del HUD tiene su color: el primero es verde, el segundo amarillo y el tercero rojo.
const TIPO_POR_HILO: Array[InventoryItem.ItemType] = [
	InventoryItem.ItemType.MEMORY,
	InventoryItem.ItemType.IMAGINATION,
	InventoryItem.ItemType.SPIRIT,
]
const FRAGMENTOS_POR_HILO: int = 3

var fragmentos_recibidos: int = 0

@onready var items_container: HBoxContainer = %ItemsContainer


func _ready() -> void:
	if not GameState.quest or GameState.quest.quest.threads_to_collect == 0:
		visible = false
		return

	for _i in TIPO_POR_HILO.size():
		items_container.add_child(ITEM_SLOT.instantiate())

	fragmentos_recibidos = GameState.quest.inventory.items.size()
	var hilos_completos := fragmentos_recibidos / FRAGMENTOS_POR_HILO
	for i: int in mini(hilos_completos, TIPO_POR_HILO.size()):
		var slot: ItemSlot = items_container.get_child(i)
		slot.start_as_filled(InventoryItem.with_type(TIPO_POR_HILO[i]))

	GameState.quest.inventory.item_collected.connect(self._on_item_collected)
	GameState.quest.inventory.item_consumed.connect(self._on_item_consumed)


func _on_item_collected(_item: InventoryItem) -> void:
	fragmentos_recibidos += 1

	if fragmentos_recibidos % FRAGMENTOS_POR_HILO == 0:
		var i := fragmentos_recibidos / FRAGMENTOS_POR_HILO - 1
		if i < TIPO_POR_HILO.size():
			var slot: ItemSlot = items_container.get_child(i)
			slot.fill(InventoryItem.with_type(TIPO_POR_HILO[i]))


func _on_item_consumed(item: InventoryItem) -> void:
	for child in items_container.get_children():
		var item_slot := child as ItemSlot
		if item_slot.is_filled_with_same_item_type_as(item):
			item_slot.free_slot()
			item_slot.self_modulate = Color.WHITE
