//
//  RNCryptTests.m
//
//  Copyright (c) 2012 Rob Napier
//
//  This code is licensed under the MIT License:
//
//  Permission is hereby granted, free of charge, to any person obtaining a 
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//


#import "RNCryptorTests.h"
#import "RNCryptor.h"

@interface RNCryptor (Private)
- (NSData *)randomDataOfLength:(size_t)length;
@end

@implementation RNCryptorTests

- (void)setUp
{
  [super setUp];

  // Set-up code here.
}

- (void)tearDown
{
  // Tear-down code here.

  [super tearDown];
}

- (void)testBlockData
{
  RNCryptor *cryptor = [RNCryptor AES128Cryptor];

  __block NSData *data = [cryptor randomDataOfLength:1024];
  NSData *key = [cryptor randomDataOfLength:kCCKeySizeAES128];
  NSData *iv = [cryptor randomDataOfLength:kCCBlockSizeAES128];

  __block NSMutableData *encrypted = [NSMutableData data];

  RNCryptorReadBlock readBlock = ^BOOL(NSData **readData, BOOL *stop, NSError **error) {
    *readData = data;
    *stop = YES;
    return YES;
  };

  RNCryptorWriteBlock writeBlock = ^BOOL(NSData *encryptedData, NSError **error) {
      [encrypted appendData:encryptedData];
      return YES;
    };

  NSError *error;
  STAssertTrue([cryptor encryptWithReadBlock:readBlock
                                  writeBlock:writeBlock
                               encryptionKey:key
                                          IV:iv
                                     HMACKey:nil
                                       error:&error], @"Failed to encrypt:", error);

  STAssertNotNil(encrypted, @"Encrypted should be non-nil");

  __block NSMutableData *decrypted = [NSMutableData data];

  readBlock = ^BOOL(NSData **readData, BOOL *stop, NSError **error) {
    *readData = encrypted;
    *stop = YES;
    return YES;
  };

  writeBlock = ^BOOL(NSData *encryptedData, NSError **error) {
    [decrypted appendData:encryptedData];
    return YES;
  };

  STAssertTrue([cryptor decryptWithReadBlock:readBlock
                                  writeBlock:writeBlock
                               encryptionKey:key
                                          IV:iv
                                     HMACKey:nil
                                       error:&error], @"Failed to decrypt:", error);

  STAssertEqualObjects(decrypted, data, @"Decrypt does not match original");
}

- (RNCryptorReadBlock)streamReadBlockForData:(NSData *)data
{
  NSInputStream *stream = [NSInputStream inputStreamWithData:data];
  [stream open];

  return ^BOOL(NSData **readData, BOOL *stop, NSError **error) {
    NSMutableData *buffer = [NSMutableData dataWithLength:1024];
    NSInteger length = [stream read:[buffer mutableBytes] maxLength:[buffer length]];
    if (length >= 0)
    {
      [buffer setLength:(NSUInteger)length];
      *readData = buffer;
    }

    if (length < sizeof(buffer))
    {
      *stop = YES;
      [stream close];
    }

    if (length < 0)
    {
      *error = [stream streamError];
      [stream close];
    }

    return (length >= 0);
  };
}

- (RNCryptorWriteBlock)streamWriteBlockWithOutputStream:(NSOutputStream **)stream
{
  *stream = [NSOutputStream outputStreamToMemory];
  [*stream open];
  RNCryptorWriteBlock writeBlock = ^BOOL(NSData *encryptedData, NSError **error) {
    NSInteger length = [*stream write:[encryptedData bytes] maxLength:[encryptedData length]];
    if (length < 0)
    {
      *error = [*stream streamError];
    }

    return (length >= 0);
  };
  return writeBlock;
}

- (void)testBlockStream
{
  RNCryptor *cryptor = [RNCryptor AES128Cryptor];

  NSData *data = [cryptor randomDataOfLength:1024*5+6];
  NSData *key = [cryptor randomDataOfLength:kCCKeySizeAES128];
  NSData *iv = [cryptor randomDataOfLength:kCCBlockSizeAES128];

  RNCryptorReadBlock readBlock = [self streamReadBlockForData:data];
  NSOutputStream *encryptedStream;
  RNCryptorWriteBlock writeBlock = [self streamWriteBlockWithOutputStream:&encryptedStream];

  NSError *error;
  STAssertTrue([cryptor encryptWithReadBlock:readBlock
                                  writeBlock:writeBlock
                               encryptionKey:key
                                          IV:iv
                                     HMACKey:nil
                                       error:&error], @"Failed to encrypt:", error);

  [encryptedStream close];
  NSData *encryptedData = [encryptedStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];

  STAssertNotNil(encryptedData, @"Encrypted should be non-nil");

  readBlock = [self streamReadBlockForData:encryptedData];
  NSOutputStream *decryptedStream;
  writeBlock = [self streamWriteBlockWithOutputStream:&decryptedStream];

  STAssertTrue([cryptor decryptWithReadBlock:readBlock
                                  writeBlock:writeBlock
                               encryptionKey:key
                                          IV:iv
                                     HMACKey:nil
                                       error:&error], @"Failed to decrypt:", error);

  [decryptedStream close];
  NSData *decryptedData = [decryptedStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
  STAssertEqualObjects(decryptedData, data, @"Decrypt does not match original");
}

//- (void)testLowLevel
//{
//  RNCryptor *cryptor = [RNCryptor AES128Cryptor];
//
//  NSData *data = [cryptor randomDataOfLength:1024];
//  NSData *key = [cryptor randomDataOfLength:kCCKeySizeAES128];
//  NSData *iv = [cryptor randomDataOfLength:kCCBlockSizeAES128];
//
//  NSInputStream *encryptStream = [NSInputStream inputStreamWithData:data];
//  [encryptStream open];
//  NSOutputStream *encryptedStream = [NSOutputStream outputStreamToMemory];
//  [encryptedStream open];
//  NSError *error;
//
//  STAssertTrue([cryptor encryptFromStream:encryptStream toStream:encryptedStream encryptionKey:key IV:iv HMACKey:nil error:&error], @"Failed encryption:%@", error);
//
//  [encryptStream close];
//  [encryptedStream close];
//
//  NSData *encrypted = [encryptedStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
//
//  NSInputStream *decryptStream = [NSInputStream inputStreamWithData:encrypted];
//  [decryptStream open];
//  NSOutputStream *decryptedStream = [NSOutputStream outputStreamToMemory];
//  [decryptedStream open];
//
//  STAssertTrue([cryptor decryptFromStream:decryptStream toStream:decryptedStream encryptionKey:key IV:iv HMACKey:nil error:&error], @"Failed decryption:%@", error);
//
//  [decryptStream close];
//  [decryptedStream close];
//
//  NSData *decrypted = [decryptedStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
//
//  STAssertEqualObjects(data, decrypted, @"Encrypted and decrypted data do not match:%@:%@", data, decrypted);
//}
//
//- (void)testSimple
//{
//  NSData *data = [@"Test" dataUsingEncoding:NSUTF8StringEncoding];
//  NSString *password = @"Password";
//
//  RNCryptor *cryptor = [RNCryptor AES128Cryptor];
//  NSInputStream *encryptStream = [NSInputStream inputStreamWithData:data];
//  [encryptStream open];
//  NSOutputStream *encryptedStream = [NSOutputStream outputStreamToMemory];
//  [encryptedStream open];
//  NSError *error;
//  STAssertTrue([cryptor encryptFromStream:encryptStream toStream:encryptedStream password:password error:&error], @"Failed encryption:%@", error);
//  [encryptStream close];
//  [encryptedStream close];
//
//  NSData *encrypted = [encryptedStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
//
//  NSInputStream *decryptStream = [NSInputStream inputStreamWithData:encrypted];
//  [decryptStream open];
//  NSOutputStream *decryptedStream = [NSOutputStream outputStreamToMemory];
//  [decryptedStream open];
//  STAssertTrue([cryptor decryptFromStream:decryptStream toStream:decryptedStream password:password error:&error], @"Failed decryption:%@", error);
//  [decryptStream close];
//  [decryptedStream close];
//
//  NSData *decrypted = [decryptedStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
//
//  STAssertEqualObjects(data, decrypted, @"Encrypted and decrypted data do not match");
//}

@end