#define DEFAULT_TASTE_SENSITIVITY 15

/mob/living
	var/last_taste_time
	var/last_taste_text

/**
 * Gets taste sensitivity of given mob
 *
 * This is used in calculating what flavours the mob can pick up,
 * with a lower number being able to pick up more distinct flavours.
 */
/mob/living/proc/get_taste_sensitivity()
	return DEFAULT_TASTE_SENSITIVITY

/mob/living/carbon/get_taste_sensitivity()
	var/obj/item/organ/tongue/tongue = get_organ_slot(ORGAN_SLOT_TONGUE)
	if(istype(tongue))
		. = tongue.taste_sensitivity
	else
		// carbons without tongues normally have TRAIT_AGEUSIA but sensible fallback
		. = DEFAULT_TASTE_SENSITIVITY

/**
 * Non-destructively tastes a reagent container
 * and gives feedback to the user.
 * Arguments:
 * * datum/reagents/from - Reagent holder to taste from.
 **/
/mob/living/proc/taste_container(datum/reagents/from)
	if(check_tasting_blocks())
		return

	var/taste_sensitivity = get_taste_sensitivity()
	var/text_output = from.generate_taste_message(src, taste_sensitivity)
	send_taste_message(text_output)

/**
 * Non-destructively tastes a reagent list
 * and gives feedback to the user.
 * Arguments:
 * * list/from - List of reagents to taste from.
 **/
/mob/living/proc/taste_list(list/from)
	if(check_tasting_blocks())
		return

	var/taste_sensitivity = get_taste_sensitivity()
	var/text_output = generate_reagents_taste_message(from, src, taste_sensitivity)
	send_taste_message(text_output)

/**
 * Check for anything blocking/overriding our tasting.
 * Returns TRUE on a block, FALSE if not.
 **/
/mob/living/proc/check_tasting_blocks()
	if(HAS_TRAIT(src, TRAIT_AGEUSIA))
		return TRUE
	if(last_taste_time + 50 >= world.time)
		return TRUE

	// Sometimes, try send a replacement message if we're hallucinating
	if(get_timed_status_effect_duration(/datum/status_effect/hallucination) > 100 SECONDS && prob(25))
		var/text_output = pick("spiders","dreams","nightmares","the future","the past","victory",\
			"defeat","pain","bliss","revenge","poison","time","space","death","life","truth","lies","justice","memory",\
			"regrets","your soul","suffering","music","noise","blood","hunger","the american way")
		send_taste_message(text_output)
		return TRUE

	return FALSE

/**
 * Attempt to send a taste message using given tastes text.
 **/
/mob/living/proc/send_taste_message(tastes_text)
	if(tastes_text == last_taste_text && last_taste_time + 100 >= world.time)
		return

	to_chat(src, span_notice("You can taste [tastes_text]."))
	// "something indescribable" -> too many tastes, not enough flavor.

	last_taste_time = world.time
	last_taste_text = tastes_text

/**
 * Gets food flags that this mob likes
 **/
/mob/living/proc/get_liked_foodtypes()
	return NONE

/mob/living/carbon/get_liked_foodtypes()
	if(HAS_TRAIT(src, TRAIT_AGEUSIA))
		return NONE
	// Handled in here since the brain trauma can't modify taste directly (/datum/brain_trauma/severe/flesh_desire)
	if(HAS_TRAIT(src, TRAIT_FLESH_DESIRE))
		return GORE | MEAT
	var/obj/item/organ/tongue/tongue = get_organ_slot(ORGAN_SLOT_TONGUE)
	. = tongue.liked_foodtypes
	if(HAS_TRAIT(src, TRAIT_VEGETARIAN))
		. &= ~MEAT

/**
 * Gets food flags that this mob dislikes
 **/
/mob/living/proc/get_disliked_foodtypes()
	if(HAS_TRAIT(src, TRAIT_VEGETARIAN))
		return MEAT
	return NONE

//hl13 edit start
/mob/living/proc/get_unpleasant_foodtypes()
	return NONE

/mob/living/carbon/get_unpleasant_foodtypes()
	if(HAS_TRAIT(src, TRAIT_AGEUSIA))
		return NONE
	var/obj/item/organ/tongue/tongue = get_organ_slot(ORGAN_SLOT_TONGUE)
	. = tongue.disliked_foodtypes

//hl13 edit end

/mob/living/carbon/get_disliked_foodtypes()
	if(HAS_TRAIT(src, TRAIT_AGEUSIA))
		return NONE
	var/obj/item/organ/tongue/tongue = get_organ_slot(ORGAN_SLOT_TONGUE)
	. = tongue.disliked_foodtypes
	if(HAS_TRAIT(src, TRAIT_VEGETARIAN))
		. |= MEAT

/**
 * Gets food flags that this mob hates
 * Toxic food is the only category that ignores ageusia, KEEP IT LIKE THAT!
 **/
/mob/living/proc/get_toxic_foodtypes()
	return TOXIC

/mob/living/carbon/get_toxic_foodtypes()
	var/obj/item/organ/tongue/tongue = get_organ_slot(ORGAN_SLOT_TONGUE)
	if(!tongue)
		return ..()
	if(HAS_TRAIT(src, TRAIT_FLESH_DESIRE))
		return VEGETABLES | DAIRY | FRUIT | FRIED
	return tongue.toxic_foodtypes

/**
 * Gets food this mob is allergic to
 * Essentially toxic food+, not only disgusting but outright lethal
 */
/mob/living/proc/get_allergic_foodtypes()
	var/datum/quirk/item_quirk/food_allergic/allergy = get_quirk(/datum/quirk/item_quirk/food_allergic)
	return allergy?.target_foodtypes || NONE

/**
 * Checks if the mob has an allergic reaction to the given food type.
 * If so, the mob will contract anaphylaxis.
 *
 * * to_foodtype: The food type to check for an allergic reaction to.
 * * chance: The chance of an allergic reaction occurring. Default is 100 (guaranteed).
 * * histamine_add: The amount of histamine to add to the mob if they are already experiencing an allergic reaction.
 *
 * Returns TRUE if the mob had an allergic reaction, FALSE otherwise.
 */
/mob/living/proc/check_allergic_reaction(to_foodtype = NONE, chance = 100, histamine_add = 0)
	if(!(get_allergic_foodtypes() & to_foodtype))
		return FALSE
	if(!prob(chance))
		return FALSE
	if(ForceContractDisease(new /datum/disease/anaphylaxis(), make_copy = FALSE, del_on_fail = TRUE))
		to_chat(src, span_warning("You feel your throat start to itch."))
		add_mood_event("allergic_food", /datum/mood_event/allergic_food)
	else if(histamine_add)
		reagents.add_reagent(/datum/reagent/toxin/histamine, histamine_add)
	return TRUE

/**
 * Gets the food reaction a mob would normally have from the given food item,
 * assuming that no check_liked callback was used in the edible component.
 *
 * Does not get called if the owner has ageusia.
 **/
/mob/living/proc/get_food_taste_reaction(obj/item/food, foodtypes)
	var/food_taste_reaction
	if(foodtypes & get_toxic_foodtypes())
		food_taste_reaction = FOOD_TOXIC
	else if(foodtypes & get_disliked_foodtypes())
		food_taste_reaction = FOOD_DISLIKED
	else if(foodtypes & get_unpleasant_foodtypes())
		food_taste_reaction = FOOD_UNPLEASANT
	else if(foodtypes & get_liked_foodtypes())
		food_taste_reaction = FOOD_LIKED
	return food_taste_reaction

/mob/living/carbon/get_food_taste_reaction(obj/item/food, foodtypes)
	var/obj/item/organ/tongue/tongue = get_organ_slot(ORGAN_SLOT_TONGUE)
	// No tongue, no tastin'
	if(!tongue?.sense_of_taste || HAS_TRAIT(src, TRAIT_AGEUSIA))
		// i hate that i have to do this, but we want to ensure toxic food is still BAD
		if(foodtypes & get_toxic_foodtypes())
			return FOOD_TOXIC
		return
	return tongue.get_food_taste_reaction(food, foodtypes)

#undef DEFAULT_TASTE_SENSITIVITY
