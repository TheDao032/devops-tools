package main

import (
	"fmt"
	"log"

	"github.com/confluentinc/confluent-kafka-go/kafka"
)

func main() {
	// Create a new Kafka consumer
	consumer, err := kafka.NewConsumer(&kafka.ConfigMap{
		"bootstrap.servers": "localhost:9092",
		"group.id":          "your_group_id",
		"auto.offset.reset": "earliest",
	})
	if err != nil {
		log.Fatalf("Failed to create consumer: %s", err)
	}
	defer consumer.Close()

	// Subscribe to the topic
	topic := "your_topic_name"
	err = consumer.SubscribeTopics([]string{topic}, nil)
	if err != nil {
		log.Fatalf("Failed to subscribe to topic: %s", err)
	}

	fmt.Println("Kafka Consumer started, waiting for messages...")

	// Consume messages
	for {
		msg, err := consumer.ReadMessage(-1)
		if err == nil {
			fmt.Printf("Message received: %s\n", string(msg.Value))
		} else {
			// Handle errors
			fmt.Printf("Consumer error: %v (%v)\n", err, msg)
		}
	}
}
