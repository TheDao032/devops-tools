package main

import (
	"fmt"
	"log"
	"os"

	"github.com/confluentinc/confluent-kafka-go/kafka"
)

func main() {
	// Create a new Kafka producer
	producer, err := kafka.NewProducer(
		&kafka.ConfigMap{"bootstrap.servers": "localhost:9092"},
	)
	if err != nil {
		log.Fatalf("Failed to create producer: %s", err)
	}
	defer producer.Close()

	// Define the topic to publish to
	topic := "your_topic_name"

	// Define the message to publish
	message := "Hello Kafka!"

	// Produce the message
	err = producer.Produce(&kafka.Message{
		TopicPartition: kafka.TopicPartition{
			Topic:     &topic,
			Partition: kafka.PartitionAny,
		},
		Value: []byte(message),
	}, nil)
	if err != nil {
		log.Fatalf("Failed to produce message: %s", err)
	}

	// Wait for message deliveries
	go func() {
		for e := range producer.Events() {
			switch ev := e.(type) {
			case *kafka.Message:
				if ev.TopicPartition.Error != nil {
					fmt.Fprintf(os.Stderr, "Failed to deliver message: %v\n", ev.TopicPartition)
				} else {
					fmt.Printf("Message delivered to topic %s [%d] at offset %v\n",
						*ev.TopicPartition.Topic, ev.TopicPartition.Partition, ev.TopicPartition.Offset)
				}
			}
		}
	}()

	// Flush to ensure all messages are delivered
	producer.Flush(15 * 1000)
}
