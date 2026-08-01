import { Module } from '@nestjs/common';
import { PieceRatesController } from './piece-rates.controller';
import { PieceRatesService } from './piece-rates.service';

@Module({
  controllers: [PieceRatesController],
  providers: [PieceRatesService],
  exports: [PieceRatesService],
})
export class PieceRatesModule {}
