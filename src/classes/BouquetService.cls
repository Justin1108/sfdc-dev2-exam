//
// The class will caculate the summary fields on both Lead and Product2 object
// In order to enforce the data integrity (the correct calculation), the "without sharing" is used here
// This will make sure all the related records will be calculated and updated
public without sharing class BouquetService {
	// Disable the update to most used color and used inventory fields
	public static Boolean disableBloomTriggerLogic = false; 

	public BouquetService() {
		
	}

	// Return the parent customer Id of the given bouquent Ids
	public Set<Id> getCustomerIds(Set<Id> bouquetIds) {
		System.debug(LoggingLevel.DEBUG, 'Enter BouquetService.getCustomerIds()');
		System.debug(LoggingLevel.DEBUG, 'bouquetIds: ' + JSON.serialize(bouquetIds));

		Set<Id> cIds = new Set<Id>();
		for (Bouquet__c bq : [SELECT Customer__c FROM Bouquet__c WHERE Id IN :bouquetIds]) {
			cIds.add(bq.Customer__c);
		}


		System.debug(LoggingLevel.DEBUG, 'Exit BouquetService.getCustomerIds()');
		return cIds;
	}

	// Update the Most_Used_Color__c field for the given customers by customerIds
	// This method will throw exception out instead of capturing within. 
	// The full data integrity should be enforced by the caller, such as the BouquetBuilder controller
	public void updateMostUsedColorForCustomers(Set<Id> customerIds) {
		System.debug(LoggingLevel.DEBUG, 'Enter BouquetService.updateMostUsedColorForCustomers()');
		System.debug(LoggingLevel.DEBUG, 'customerIds: ' + JSON.serialize(customerIds));

		// select and lock the customer/lead records for data integrity
		List<Lead> customers = [SELECT Id FROM Lead WHERE Id IN :customerIds FOR UPDATE];
		AggregateResult[] results = [SELECT Bouquet__r.Customer__c, Flower__r.Color__c, SUM(Quantity__c) 
										FROM Bloom__c 
										WHERE Bouquet__r.Customer__c IN :customerIds 
										GROUP BY Bouquet__r.Customer__c, Flower__r.Color__c 
										ORDER BY SUM(Quantity__c) DESC, Flower__r.Color__c];

		// Customers for update
		Map<Id, Lead> customerMap = new Map<Id, Lead>();
		for (AggregateResult r : results) {
			Id customerId = (Id)r.get('Customer__c');
			String color = String.valueOf(r.get('Color__c'));

			Lead customer = customerMap.get(customerId);
			if (customer != null) {
				// Skip, because the color has been set by result
			} else {
				customer = new Lead(Id=customerId, Most_Used_Color__c=color);
				customerMap.put(customer.Id, customer);
			}
		}


		// Update the customers
		// If there're DML error(s), DML exception will be thrown and bubble up to the caller
		update customerMap.values();

		System.debug(LoggingLevel.DEBUG, 'Exit BouquetService.updateMostUsedColorForCustomers()');
	}

	// Update the Inventory_Used__c field for the given flowers/Product2 by the flowerIds
	// This method will throw exception out instead of capturing within. 
	// The full data integrity should be enforced by the caller, such as the BouquetBuilder controller
	public void updateUsedInventoryForFlowers(Set<Id> flowerIds) {
		System.debug(LoggingLevel.DEBUG, 'Enter BouquetService.updateUsedInventoryForFlowers()');
		System.debug(LoggingLevel.DEBUG, 'flowerIds: ' + JSON.serialize(flowerIds));

		// Lock the flower records before update for data integrity
		Map<Id, Product2> flowers = new Map<Id, Product2>([SELECT Id, Initial_Inventory__c FROM Product2 WHERE Id IN :flowerIds FOR UPDATE]);

		AggregateResult[] results = [SELECT Flower__c, SUM(Quantity__c) FROM Bloom__c WHERE Flower__c IN :flowerIds GROUP BY Flower__c];
		Map<Id, Product2> flowerMap = new Map<Id, Product2>();
		for (AggregateResult r : results) {
			Id flowerId = (Id)r.get('Flower__c');

			Integer quantity = Integer.valueOf(r.get('expr0'));
			Product2 flower = flowers.get(flowerId);
			// We don't need it because a validation rule has enable it
			//if (quantity > flower.Initial_Inventory__c) quantity = (Integer)flower.Initial_Inventory__c; // The used amount should not bigger than initial amount

			flowerMap.put(flowerId, new Product2(
				Id = flowerId,
				Inventory_Used__c = quantity
				));

			flowers.remove(flowerId);
		}

		if (flowers.size() > 0) {
			// Bloom record(s) have been removed, need to clear the Inventory_Used__c value
			for (Product2 f : flowers.values()) {
				flowerMap.put(f.Id, new Product2(
					Id = f.Id,
					Inventory_Used__c = 0
					));
			}
		}

		// Update the Product2/Flowers
		// If there're DML error(s), the caller should capture the exception and handle it.
		update flowerMap.values();

		System.debug(LoggingLevel.DEBUG, 'Exit BouquetService.updateUsedInventoryForFlowers()');
	}


}