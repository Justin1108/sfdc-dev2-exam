trigger BloomTrigger on Bloom__c (after insert, after update, after delete) {
	if (!BouquetService.disableBloomTriggerLogic) {
		Set<Id> bouquetIds = new Set<Id>();
		Set<Id> flowerIds = new Set<Id>();
		if (Trigger.isInsert || Trigger.isUpdate) {
			// Trigger.new
			for (Bloom__c b : (List<Bloom__c>)Trigger.new) {
				bouquetIds.add(b.Bouquet__c);
				flowerIds.add(b.Flower__c);
			}
		} else if (Trigger.isDelete) {
			// Trigger.old
			for (Bloom__c b : (List<Bloom__c>)Trigger.old) {
				bouquetIds.add(b.Bouquet__c);
				flowerIds.add(b.Flower__c);
			}
		}

		if (bouquetIds.size() > 0) {
			BouquetService service = new BouquetService();
			Set<Id> customerIds = service.getCustomerIds(bouquetIds);

			service.updateUsedInventoryForFlowers(flowerIds);
			service.updateMostUsedColorForCustomers(customerIds);
		}
	}
}